#!/usr/bin/env python3
"""Offline contract checks for the llm-d-sc routing profile."""

import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT / "configs/llm-d-sc/praxis.yaml"
IMAGES_PATH = ROOT / "configs/llm-d-sc/images.env"
INTEGRATION_PATH = ROOT / "tests/llm-d-sc/integration.py"


class LlmDScConfig(unittest.TestCase):
    def setUp(self):
        self.config = yaml.safe_load(CONFIG_PATH.read_text())

    def test_filter_chain_has_one_cluster_selector(self):
        filters = self.config["filter_chains"][0]["filters"]
        kinds = [item["filter"] for item in filters]
        self.assertEqual(
            kinds,
            ["request_id", "access_log", "static_response", "llm_d_sc", "load_balancer"],
        )
        self.assertNotIn("router", kinds)

    def test_labels_map_to_expected_backends(self):
        filters = self.config["filter_chains"][0]["filters"]
        classifier = next(item for item in filters if item["filter"] == "llm_d_sc")
        routes = {item["label"]: item["cluster"] for item in classifier["routes"]}
        self.assertEqual(
            routes,
            {
                "SIMPLE": "vllm-cpu",
                "MEDIUM": "vllm-cpu",
                "COMPLEX": "vllm-gpu",
                "REASONING": "vllm-gpu",
            },
        )
        self.assertEqual(classifier["default_cluster"], "vllm-cpu")
        self.assertEqual(classifier["on_unavailable"], "default_cluster")
        self.assertEqual(classifier["status_on_reject"], 503)

    def test_endpoints_stay_on_the_private_container_network(self):
        filters = self.config["filter_chains"][0]["filters"]
        classifier = next(item for item in filters if item["filter"] == "llm_d_sc")
        load_balancer = next(item for item in filters if item["filter"] == "load_balancer")
        self.assertEqual(classifier["endpoint"], "llm-d-sc:50051")
        self.assertEqual(
            {item["name"]: item["endpoints"] for item in load_balancer["clusters"]},
            {
                "vllm-cpu": ["trace-ui:8081"],
                "vllm-gpu": ["trace-ui:8082"],
            },
        )

    def test_admin_listener_stays_private(self):
        self.assertEqual(self.config["admin"]["address"], "127.0.0.1:9901")
        self.assertEqual(self.config["listeners"][0]["address"], "0.0.0.0:8080")

    def test_optional_ui_images_are_digest_pinned(self):
        images = {}
        for line in IMAGES_PATH.read_text().splitlines():
            if line and not line.startswith("#"):
                key, value = line.split("=", 1)
                images[key] = value
        self.assertIn("sha256:", images["LLM_D_SC_OPENWEBUI_IMAGE"])
        self.assertIn("sha256:", images["LLM_D_SC_TRACE_IMAGE"])
        self.assertNotIn(":latest", " ".join(images.values()))

    def test_remote_gpu_mode_requires_real_mode(self):
        spec = importlib.util.spec_from_file_location("llm_d_sc_integration", INTEGRATION_PATH)
        integration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(integration)
        with self.assertRaisesRegex(ValueError, "--remote-gpu requires --real"):
            integration.main(remote_gpu="gpu.example.invalid")

    def test_gpu_only_mode_has_explicit_contracts(self):
        spec = importlib.util.spec_from_file_location("llm_d_sc_integration", INTEGRATION_PATH)
        integration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(integration)
        with self.assertRaisesRegex(ValueError, "--gpu-only requires --real"):
            integration.main(gpu_only=True)
        with self.assertRaisesRegex(ValueError, "--gpu-only cannot use --remote-gpu"):
            integration.main(real=True, gpu_only=True, remote_gpu="gpu.example.invalid")

    def test_webui_request_forwards_timeout(self):
        spec = importlib.util.spec_from_file_location("llm_d_sc_integration", INTEGRATION_PATH)
        integration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(integration)
        with mock.patch.object(
            integration,
            "json_request",
            return_value={"choices": [{"message": {"content": "ok"}}]},
        ) as json_request:
            content = integration.webui_request(
                8080, "token", "prompt", max_tokens=128, timeout=600,
                chat_template_kwargs={"enable_thinking": False},
            )
        self.assertEqual(content, "ok")
        self.assertEqual(json_request.call_args.kwargs["timeout"], 600)
        self.assertEqual(
            json_request.call_args.args[1]["chat_template_kwargs"],
            {"enable_thinking": False},
        )


if __name__ == "__main__":
    if not __debug__ or sys.flags.optimize:
        raise SystemExit("Run tests without Python -O or PYTHONOPTIMIZE")
    unittest.main()
