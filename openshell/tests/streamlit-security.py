#!/usr/bin/env python3
"""Contracts for the Streamlit before/after OpenShell demo."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import unittest
import urllib.request

import yaml


ROOT = Path(__file__).resolve().parents[2]
DEMO = ROOT / "openshell/demos/streamlit-security"


class StreamlitSecurityTests(unittest.TestCase):
    def call_model(self, ticket, **arguments):
        sys.path.insert(0, str(DEMO))
        try:
            from model_client import call_model

            return call_model(ticket, **arguments)
        finally:
            sys.path.remove(str(DEMO))

    def test_policy_confines_the_application_directory(self):
        policy = yaml.safe_load((DEMO / "policy.yaml").read_text())
        filesystem = policy["filesystem_policy"]
        self.assertFalse(filesystem["include_workdir"])
        self.assertIn("/opt/openshell-demo", filesystem["read_only"])
        self.assertIn("/lib", filesystem["read_only"])
        self.assertEqual(filesystem["read_write"], ["/tmp", "/dev/null"])
        self.assertEqual(policy["landlock"]["compatibility"], "hard_requirement")
        self.assertEqual(policy["process"]["run_as_user"], "1500")
        self.assertEqual(policy["process"]["run_as_group"], "1500")
        self.assertEqual(policy["network_policies"], {})

    def test_model_request_sends_credential_and_model_selection(self):
        requests = []

        class FakeResponse:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc_value, traceback):
                return False

            def read(self):
                return json.dumps(
                    {"choices": [{"message": {"content": "Safe summary"}}]}
                ).encode()

        class FakeOpener:
            def open(self, request, timeout):
                del timeout
                requests.append(request)
                return FakeResponse()

        response = self.call_model(
            "Checkout is slow",
            base_url="https://api.openai.com/v1",
            api_key="opaque-placeholder",
            model="gpt-5.5",
            opener=FakeOpener(),
        )

        self.assertEqual(response, "Safe summary")
        request = requests[0]
        self.assertEqual(request.headers["Authorization"], "Bearer opaque-placeholder")
        body = json.loads(request.data)
        self.assertEqual(body["model"], "gpt-5.5")

    def test_provider_profiles_bind_credentials_to_native_endpoints(self):
        openai = yaml.safe_load((DEMO / "providers/openai.yaml").read_text())
        compatible = yaml.safe_load(
            (DEMO / "providers/openai-compatible.yaml").read_text()
        )
        for profile in (openai, compatible):
            self.assertEqual(profile["credentials"][0]["env_vars"], ["OPENAI_API_KEY"])
            self.assertEqual(profile["binaries"], ["/usr/local/bin/python3.*"])
            endpoint = profile["endpoints"][0]
            self.assertEqual(endpoint["protocol"], "rest")
            self.assertEqual(endpoint["enforcement"], "enforce")
        self.assertEqual(openai["endpoints"][0]["host"], "api.openai.com")
        self.assertEqual(openai["endpoints"][0]["port"], 443)

    def test_documentation_puts_model_requirements_first(self):
        guide = (ROOT / "docs/examples/streamlit-security/README.md").read_text()
        self.assertLess(guide.index("Before you start"), guide.index("Run the unsafe version"))
        self.assertIn("OpenAI-compatible endpoint", guide)
        self.assertIn("openshell profile import", guide)
        self.assertIn("openshell provider create", guide)

    def test_documentation_explains_where_to_run_the_demo(self):
        guide = (ROOT / "docs/examples/streamlit-security/README.md").read_text()
        self.assertIn("AWS is not required", guide)
        self.assertIn("/usr/share/secure-single-server", guide)
        self.assertIn("/opt/secure-single-server", guide)
        self.assertIn("Landlock ABI 3", guide)
        self.assertIn("ordinary nested container", guide)

    def test_root_readme_introduces_the_example_catalog(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("docs/examples/README.md", readme)
        self.assertIn("docs/examples/streamlit-security/README.md", readme)
        self.assertLess(
            readme.index("docs/examples/streamlit-security/README.md"),
            readme.index("docs/examples/opencode-pr-queue/README.md"),
        )
        self.assertIn("/usr/share/secure-single-server", readme)
        self.assertIn("/opt/secure-single-server", readme)

    def test_demo_entry_points_are_executable(self):
        for name in ("run-unsafe.sh", "run-safe.sh", "verify.sh"):
            path = DEMO / name
            self.assertTrue(path.is_file())
            self.assertTrue(os.access(path, os.X_OK), name)

    def test_safe_runner_exposes_service_after_creation(self):
        script = (DEMO / "run-safe.sh").read_text()
        self.assertIn("openshell service expose", script)
        self.assertNotIn("--forward 8501", script)

    def test_safe_runner_launches_authorized_interpreter(self):
        script = (DEMO / "run-safe.sh").read_text()
        self.assertIn("/usr/local/bin/python3 -m streamlit", script)

    def test_safe_runner_allows_gateway_websocket_origin(self):
        script = (DEMO / "run-safe.sh").read_text()
        self.assertIn(
            "--server.corsAllowedOrigins "
            '"http://default--${SANDBOX}--streamlit.openshell.localhost:8090"',
            script,
        )

    def test_verifier_has_positive_write_control(self):
        script = (DEMO / "verify.sh").read_text()
        self.assertIn("/tmp/verify-write", script)
        self.assertIn("/opt/openshell-demo/verify-leak", script)
        self.assertIn("/opt/openshell-demo-secret", script)

    def test_verifier_requires_permission_denied_evidence(self):
        script = (DEMO / "verify.sh").read_text()
        self.assertIn("SANDBOX_EXEC_STATUS", script)
        self.assertIn("Permission denied", script)
        self.assertIn("EACCES", script)

    def test_docker_image_runs_streamlit_as_non_root(self):
        dockerfile = (DEMO / "Dockerfile").read_text()
        self.assertIn("USER 1500:1500", dockerfile)
        self.assertLess(dockerfile.index("COPY --chown"), dockerfile.index("USER"))

    def test_demo_uses_synthetic_file_read_target(self):
        app = (DEMO / "app.py").read_text()
        dockerfile = (DEMO / "Dockerfile").read_text()
        policy = (DEMO / "policy.yaml").read_text()
        guide = (ROOT / "docs/examples/streamlit-security/README.md").read_text()
        self.assertIn("/opt/openshell-demo-secret", app)
        self.assertIn("demo-file-read-marker-not-a-real-secret", dockerfile)
        self.assertIn("Run file-read diagnostic", app)
        self.assertNotIn("/opt/openshell-demo-secret", policy)
        self.assertIn("synthetic marker", guide)
        self.assertIn("/etc/passwd", guide)
        self.assertIn("/etc/shadow", guide)
        self.assertIn("Do not replace", guide)

    def test_page_explains_model_input_and_local_diagnostics(self):
        app = (DEMO / "app.py").read_text()
        self.assertIn("The model does not run", app)
        self.assertIn("fixed commands in the application process", app)
        self.assertIn("prompt-injected ticket", app)
        self.assertIn("application tampering", app)
        self.assertIn("data exposure", app)

    def test_page_has_concise_before_after_summary(self):
        app = (DEMO / "app.py").read_text()
        self.assertIn("only the blast radius changes", app)
        self.assertIn("| | Ordinary container | OpenShell sandbox |", app)
        self.assertIn("Opaque placeholder; OpenShell substitutes the key", app)
        self.assertIn("Model access works while filesystem access is contained", app)
        self.assertNotIn("The same app, first with a real key", app)

    def test_page_hides_streamlit_deploy_button(self):
        app = (DEMO / "app.py").read_text()
        self.assertIn('[data-testid="stAppDeployButton"]', app)
        self.assertIn("unsafe_allow_html=True", app)

    def test_demo_uses_marker_not_secret(self):
        app = (DEMO / "app.py").read_text()
        self.assertIn("DEMO_MARKER", app)
        self.assertNotIn("DEMO_FAKE_SECRET", app)

    def test_documentation_mentions_remote_tunnel(self):
        guide = (ROOT / "docs/examples/streamlit-security/README.md").read_text()
        self.assertIn("ssh -N -L 8501:127.0.0.1:8501", guide)
        self.assertIn("ssh -N -L 8090:127.0.0.1:8090", guide)
        self.assertIn("routes exposed services by hostname", guide)
        self.assertIn("http://localhost:8090", guide)
        self.assertLess(
            guide.index("ssh -N -L 8501:127.0.0.1:8501"),
            guide.index("## Run the unsafe version"),
        )

    def test_demo_files_do_not_contain_real_openai_keys(self):
        key_pattern = re.compile(r"sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}")
        paths = [
            *DEMO.rglob("*"),
            *(ROOT / "docs/examples/streamlit-security").rglob("*"),
        ]
        for path in paths:
            if not path.is_file():
                continue
            with path.open(encoding="utf-8", errors="replace") as stream:
                content = stream.read()
            self.assertIsNone(
                key_pattern.search(content),
                f"real-looking OpenAI key in {path.relative_to(ROOT)}",
            )


if __name__ == "__main__":
    unittest.main()
