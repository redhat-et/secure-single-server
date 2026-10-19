#!/usr/bin/env python3
"""Exercise llm-d-sc routing without OpenShift, KServe, or Compose."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/common"))
from evidence import save

ENGINE = os.environ.get("CONTAINER_ENGINE", "podman")
PRAXIS_IMAGE = os.environ.get(
    "LLM_D_SC_PRAXIS_IMAGE",
    "quay.io/rmalone/praxis-llm-d-sc@sha256:"
    "5a72648501df1f414745442ca0e79ba5bff5c1d6b9238727f5f994755bc367d8",
)
CLASSIFIER_IMAGE = os.environ.get(
    "LLM_D_SC_CLASSIFIER_IMAGE",
    "quay.io/rmalone/llm-d-sc@sha256:"
    "2a4e947ce1f6973535f8b6ff394d723d8342f5bac3fff1960d485740b4412e56",
)
MODELCAR_IMAGE = os.environ.get(
    "LLM_D_SC_MODELCAR_IMAGE",
    "quay.io/rmalone/llm-d-sc-modelcar@sha256:"
    "84a4b058ca197f160ba8da014ac5dd2e1852acabc590a12ce54e035dbe6b2496",
)
MOCK_IMAGE = os.environ.get(
    "LLM_D_SC_MOCK_IMAGE",
    "docker.io/library/python@sha256:"
    "519591d6871b7bc437060736b9f7456b8731f1499a57e22e6c285135ae657bf7",
)

BACKEND_SOURCE = r'''
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request_body = json.loads(self.rfile.read(length) or b"{}")
        request_headers = {
            key.lower(): value
            for key, value in self.headers.items()
            if key.lower().startswith("x-llm-d-sc-")
        }
        payload = {
            "backend": os.environ["BACKEND_NAME"],
            "request_headers": request_headers,
            "request_model": request_body.get("model"),
        }
        response = {
            "id": "chatcmpl-llm-d-sc-test",
            "object": "chat.completion",
            "created": 0,
            "model": request_body.get("model", "unknown"),
            "choices": [{
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": json.dumps(payload, sort_keys=True),
                },
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        }
        data = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return

ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
'''


def run(*args, capture=True):
    result = subprocess.run(
        [str(item) for item in args],
        capture_output=capture,
        text=True,
        timeout=300,
        check=False,
    )
    if result.returncode:
        output = result.stderr if capture and result.stderr else result.stdout if capture else ""
        raise RuntimeError(output or f"command failed: {' '.join(map(str, args))}")
    return result.stdout.strip() if capture else ""


def container_logs(name):
    result = subprocess.run(
        [ENGINE, "logs", name],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    return (result.stdout + result.stderr).strip()


def inspect(image, format_string):
    return run(ENGINE, "image", "inspect", image, "--format", format_string)


def prepare_images():
    for image in (PRAXIS_IMAGE, CLASSIFIER_IMAGE, MODELCAR_IMAGE, MOCK_IMAGE):
        available = subprocess.run(
            [ENGINE, "image", "inspect", image],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if available.returncode:
            run(ENGINE, "pull", image)
        architecture = inspect(image, "{{.Architecture}}")
        if architecture != "amd64":
            raise AssertionError(f"{image} is linux/{architecture}, expected linux/amd64")
    praxis_user = inspect(PRAXIS_IMAGE, "{{.Config.User}}")
    if not praxis_user or praxis_user in ("0", "0:0", "root"):
        raise AssertionError(f"Praxis image must declare a non-root user, found {praxis_user!r}")


def bind(source, target):
    return ["--volume", f"{source}:{target}:ro,Z"]


def wait_for_classifier(name, attempts=120):
    last_log = ""
    for attempt in range(attempts):
        state = run(ENGINE, "container", "inspect", "--format", "{{.State.Status}}", name)
        if state != "running":
            raise AssertionError(f"classifier is {state}, expected running")
        last_log = container_logs(name)
        if "READY" in last_log:
            return
        time.sleep(1)
    raise AssertionError(f"classifier did not report readiness; logs:\n{last_log}")


def request(port, prompt):
    body = json.dumps({
        "model": "Semantic-Qwen",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 16,
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.build_opener(
        urllib.request.ProxyHandler({})
    ).open(request, timeout=10) as response:
        if response.status != 200:
            raise AssertionError(f"gateway returned HTTP {response.status}")
        completion = json.load(response)
    content = completion["choices"][0]["message"]["content"]
    return json.loads(content)


def wait_for_gateway(port, attempts=60):
    last_error = None
    for _ in range(attempts):
        try:
            with urllib.request.build_opener(
                urllib.request.ProxyHandler({})
            ).open(f"http://127.0.0.1:{port}/v1/models", timeout=2) as response:
                models = json.load(response)
            assert [item["id"] for item in models["data"]] == ["Semantic-Qwen"]
            return
        except (OSError, urllib.error.URLError, AssertionError, json.JSONDecodeError) as error:
            last_error = error
            time.sleep(0.5)
    raise AssertionError(f"gateway did not become ready: {last_error}")


def assert_route(result, label, backend, minimum_score):
    headers = result["request_headers"]
    actual_label = headers.get("x-llm-d-sc-label")
    actual_status = headers.get("x-llm-d-sc-status")
    actual_score = float(headers.get("x-llm-d-sc-score", "-1"))
    assert actual_label == label, f"expected {label}, received {actual_label}"
    assert actual_status == "OK", f"expected OK status, received {actual_status}"
    assert actual_score >= minimum_score, f"{label} score {actual_score} is below {minimum_score}"
    assert result["backend"] == backend, f"expected {backend}, received {result['backend']}"
    return {
        "label": actual_label,
        "score": actual_score,
        "status": actual_status,
        "backend": result["backend"],
    }


def diagnostics(*containers):
    for container in containers:
        if not container:
            continue
        state = subprocess.run(
            [ENGINE, "container", "inspect", "--format", "{{.State.Status}}", container],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        logs = subprocess.run(
            [ENGINE, "logs", container],
            capture_output=True,
            text=True,
            check=False,
        )
        print(f"--- {container} ({state or 'absent'}) ---", flush=True)
        print(logs.stdout[-12000:] or logs.stderr[-12000:], flush=True)


def main():
    os.environ.setdefault("TEST_EVIDENCE_DIR", "evidence/llm-d-sc")
    prefix = "llm-d-sc-test-" + uuid.uuid4().hex[:12]
    network = prefix + "-network"
    model_volume = prefix + "-model"
    classifier = prefix + "-classifier"
    praxis = prefix + "-praxis"
    cpu_backend = prefix + "-cpu"
    gpu_backend = prefix + "-gpu"
    result = {
        "engine": ENGINE,
        "images": {
            "praxis": PRAXIS_IMAGE,
            "classifier": CLASSIFIER_IMAGE,
            "modelcar": MODELCAR_IMAGE,
            "mock": MOCK_IMAGE,
        },
        "status": "running",
        "routes": [],
    }
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        backend = work / "backend.py"
        backend.write_text(BACKEND_SOURCE)
        backend.chmod(0o644)
        try:
            prepare_images()
            run(ENGINE, "network", "create", network)
            run(ENGINE, "volume", "create", model_volume)
            run(
                ENGINE, "run", "--rm",
                "--volume", f"{model_volume}:/shared",
                "--user", "0:0",
                "--read-only",
                "--cap-drop", "all",
                "--security-opt", "no-new-privileges",
                MODELCAR_IMAGE,
                "/bin/sh", "-c", "cp -R /models/. /shared/",
            )

            for name, backend_name, alias in (
                (cpu_backend, "vllm-cpu", "vllm-cpu"),
                (gpu_backend, "vllm-gpu", "vllm-gpu"),
            ):
                run(
                    ENGINE, "run", "--detach", "--name", name,
                    "--network", network, "--network-alias", alias,
                    "--read-only", "--cap-drop", "all",
                    "--security-opt", "no-new-privileges",
                    "--user", "1001:1001", "--tmpfs", "/tmp",
                    "--env", "PYTHONDONTWRITEBYTECODE=1",
                    "--env", f"BACKEND_NAME={backend_name}",
                    *bind(backend, "/backend.py"),
                    MOCK_IMAGE, "python3", "/backend.py",
                )

            run(
                ENGINE, "run", "--detach", "--name", classifier,
                "--network", network, "--network-alias", "llm-d-sc",
                "--read-only", "--cap-drop", "all",
                "--security-opt", "no-new-privileges",
                "--tmpfs", "/tmp",
                "--volume", f"{model_volume}:/models:ro",
                "--env", "LLM_D_SC_MODEL_DIR=/models",
                "--env", "LLM_D_SC_CLASSIFIER=complexity",
                "--env", "LLM_D_SC_LISTEN=0.0.0.0:50051",
                CLASSIFIER_IMAGE,
            )
            wait_for_classifier(classifier)

            run(
                ENGINE, "run", "--detach", "--name", praxis,
                "--network", network, "--network-alias", "praxis",
                "--read-only", "--cap-drop", "all",
                "--security-opt", "no-new-privileges",
                "--tmpfs", "/tmp",
                "--publish", "127.0.0.1::8080",
                *bind(ROOT / "configs/llm-d-sc/praxis.yaml", "/etc/praxis/config.yaml"),
                PRAXIS_IMAGE,
            )
            port = run(ENGINE, "port", praxis, "8080/tcp").rsplit(":", 1)[1]
            wait_for_gateway(port)

            simple = assert_route(
                request(port, "What is the capital of France?"),
                "SIMPLE", "vllm-cpu", 0.99,
            )
            reasoning = assert_route(
                request(
                    port,
                    "Analyze a multi-step proof, identify every invalid inference, "
                    "and justify a corrected formal argument.",
                ),
                "REASONING", "vllm-gpu", 0.99,
            )
            result["routes"] = [simple, reasoning]
            result["status"] = "passed"
            print(json.dumps(result, indent=2))
            return 0
        except BaseException as error:
            result["status"] = "failed"
            result["error"] = str(error)
            diagnostics(praxis, classifier, cpu_backend, gpu_backend)
            print(json.dumps(result, indent=2), file=sys.stderr)
            return 1
        finally:
            for container in (praxis, classifier, cpu_backend, gpu_backend):
                subprocess.run(
                    [ENGINE, "rm", "--force", container],
                    capture_output=True,
                    check=False,
                )
            subprocess.run(
                [ENGINE, "volume", "rm", model_volume],
                capture_output=True,
                check=False,
            )
            subprocess.run(
                [ENGINE, "network", "rm", network],
                capture_output=True,
                check=False,
            )
            save("integration", result)


if __name__ == "__main__":
    if not __debug__ or os.environ.get("PYTHONOPTIMIZE"):
        raise SystemExit("Run tests without Python -O/PYTHONOPTIMIZE")
    raise SystemExit(main())
