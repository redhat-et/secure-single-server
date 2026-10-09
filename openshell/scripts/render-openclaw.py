#!/usr/bin/env python3
"""Render a non-secret OpenClaw provider configuration for a sandbox."""
import json
import sys

source, destination, port, model, prefix = sys.argv[1:]
if not model.strip() or any(ord(character) < 32 for character in model):
    raise SystemExit("OPENSHELL_MODEL_ID must be a nonempty model id without control characters")
with open(source) as stream:
    config = json.load(stream)
try:
    provider = config["models"]["providers"]["praxis"]
except (KeyError, TypeError):
    raise SystemExit("--config requires an OpenClaw Praxis template (configs/openshell-praxis/openclaw)")
provider["baseUrl"] = f"http://host.openshell.internal:{port}{prefix}/v1"
provider["models"][0]["id"] = model
config["agents"]["defaults"]["model"]["primary"] = "praxis/" + model
# Only the local vLLM template supplies model-specific request parameters.
models = config["agents"]["defaults"].get("models", {})
if "praxis/@@MODEL_ID@@" in models:
    models["praxis/" + model] = models.pop("praxis/@@MODEL_ID@@")
with open(destination, "w") as stream:
    json.dump(config, stream, indent=2)
    stream.write("\n")
