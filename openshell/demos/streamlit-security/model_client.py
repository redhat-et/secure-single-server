"""Model client for the Streamlit before/after OpenShell demo."""
from __future__ import annotations

import json
import urllib.request


SYSTEM_MESSAGE = {
    "role": "system",
    "content": (
        "You are a support-ticket triage assistant. Return a concise summary "
        "and one recommended next step."
    ),
}


def call_model(
    ticket: str,
    *,
    base_url: str,
    api_key: str,
    model: str,
    opener: urllib.request.OpenerDirector | None = None,
) -> str:
    if not ticket.strip():
        raise ValueError("ticket must not be empty")
    if not api_key:
        raise ValueError("OPENAI_API_KEY is required")
    if not model:
        raise ValueError("OPENAI_MODEL is required")

    headers = {"Authorization": f"Bearer {api_key}"}
    payload = {
        "model": model,
        "messages": [SYSTEM_MESSAGE, {"role": "user", "content": ticket}],
        "temperature": 0.1,
        "max_tokens": 300,
    }

    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    )
    response_opener = opener or urllib.request.build_opener()
    with response_opener.open(request, timeout=60.0) as response:
        if not 200 <= response.status < 300:
            raise ValueError(f"model request failed with status {response.status}")
        document = json.load(response)

    try:
        content = document["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as error:
        raise ValueError("model response has no assistant content") from error
    if not isinstance(content, str) or not content.strip():
        raise ValueError("model response has no assistant content")
    return content
