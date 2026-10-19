#!/usr/bin/env python3
"""Offline contract checks for the llm-d-sc routing profile."""

from pathlib import Path
import sys
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT / "configs/llm-d-sc/praxis.yaml"


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
                "vllm-cpu": ["vllm-cpu:8000"],
                "vllm-gpu": ["vllm-gpu:8000"],
            },
        )

    def test_admin_listener_stays_private(self):
        self.assertEqual(self.config["admin"]["address"], "127.0.0.1:9901")
        self.assertEqual(self.config["listeners"][0]["address"], "0.0.0.0:8080")


if __name__ == "__main__":
    if not __debug__ or sys.flags.optimize:
        raise SystemExit("Run tests without Python -O or PYTHONOPTIMIZE")
    unittest.main()
