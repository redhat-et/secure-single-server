#!/usr/bin/env python3
"""Small OpenAI-compatible relay and trace dashboard for llm-d-sc."""

from __future__ import annotations

from datetime import datetime, timezone
import html
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sqlite3
import threading
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DATABASE = Path(os.environ.get("TRACE_DB_PATH", "/tmp/traces.db"))
UPSTREAM = os.environ.get("PRAXIS_UPSTREAM", "http://praxis:8080").rstrip("/")
CPU_UPSTREAM = os.environ.get("CPU_UPSTREAM", "http://vllm-cpu:8000").rstrip("/")
GPU_UPSTREAM = os.environ.get("GPU_UPSTREAM", "http://vllm-gpu:8000").rstrip("/")
MAX_TRACES = int(os.environ.get("TRACE_MAX_TRACES", "250"))
DB_LOCK = threading.Lock()
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


def connection() -> sqlite3.Connection:
    DATABASE.parent.mkdir(parents=True, exist_ok=True)
    database = sqlite3.connect(DATABASE)
    database.execute(
        """CREATE TABLE IF NOT EXISTS traces (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            method TEXT NOT NULL,
            path TEXT NOT NULL,
            request_id TEXT,
            status INTEGER,
            label TEXT,
            route TEXT,
            score TEXT,
            duration_ms INTEGER,
            error TEXT,
            question TEXT
        )"""
    )
    return database


def create_trace(trace_id: str, method: str, path: str, question: str | None) -> None:
    started = datetime.now(timezone.utc).isoformat()
    with DB_LOCK, connection() as database:
        database.execute(
            """INSERT INTO traces
               (id, started_at, method, path, request_id, label, route, score,
                duration_ms, question)
               VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?)""",
            (trace_id, started, method, path, question),
        )


def complete_trace(trace_id: str, status: int | None, headers, duration_ms: int,
                   error: str | None = None) -> None:
    completed = datetime.now(timezone.utc).isoformat()
    lowered = {key.lower(): value for key, value in headers.items()} if headers else {}
    request_id = lowered.get("x-request-id")
    label = lowered.get("x-demo-classification")
    route = lowered.get("x-demo-route")
    if route is None and label:
        route = "vllm-gpu" if label.upper() in {"COMPLEX", "REASONING"} else "vllm-cpu"
    score = lowered.get("x-llm-d-sc-score")
    with DB_LOCK, connection() as database:
        database.execute(
            """UPDATE traces SET completed_at = ?, request_id = ?, status = ?,
               label = ?, route = ?, score = ?, duration_ms = ?, error = ?
               WHERE id = ?""",
            (completed, request_id, status, label, route, score, duration_ms,
             error, trace_id),
        )
        if MAX_TRACES >= 0:
            database.execute(
                """DELETE FROM traces WHERE id NOT IN (
                       SELECT id FROM traces ORDER BY started_at DESC LIMIT ?
                   )""",
                (MAX_TRACES,),
            )


def traces() -> list[dict[str, object]]:
    with DB_LOCK, connection() as database:
        database.row_factory = sqlite3.Row
        rows = database.execute(
            "SELECT * FROM traces ORDER BY started_at DESC LIMIT ?",
            (MAX_TRACES if MAX_TRACES >= 0 else -1,),
        ).fetchall()
    return [dict(row) for row in rows]


def clear_traces() -> None:
    with DB_LOCK, connection() as database:
        database.execute("DELETE FROM traces")


def question_from(body: bytes) -> str | None:
    try:
        messages = json.loads(body or b"{}").get("messages", [])
    except (UnicodeDecodeError, json.JSONDecodeError, AttributeError):
        return None
    for message in reversed(messages if isinstance(messages, list) else []):
        if not isinstance(message, dict) or message.get("role") != "user":
            continue
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()[:500]
        if isinstance(content, list):
            parts = [
                item.get("text", "").strip()
                for item in content
                if isinstance(item, dict) and isinstance(item.get("text"), str)
            ]
            if parts:
                return "\n".join(parts)[:500]
    return None


def dashboard(rows: list[dict[str, object]]) -> bytes:
    def text(value):
        return html.escape("" if value is None else str(value))

    table_rows = []
    for row in rows:
        table_rows.append(
            "<tr>"
            f"<td>{text(row['started_at'])}</td>"
            f"<td><code>{text(row['method'])}</code> {text(row['path'])}</td>"
            f"<td>{text(row['label'])}</td>"
            f"<td>{text(row['route'])}</td>"
            f"<td>{text(row['score'])}</td>"
            f"<td>{text(row['status'])}</td>"
            f"<td>{text(row['duration_ms'])}</td>"
            "</tr>"
        )
    body = "".join(table_rows) or '<tr><td colspan="7">No requests recorded.</td></tr>'
    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="refresh" content="2">
  <title>llm-d-sc routing traces</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{ margin: 2rem; font: 15px/1.5 system-ui, sans-serif; background: #111827; color: #e5e7eb; }}
    h1 {{ font-size: 1.5rem; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #374151; padding: .5rem; text-align: left; vertical-align: top; }}
    th {{ background: #1f2937; }}
    code {{ color: #93c5fd; }}
  </style>
</head>
<body>
  <h1>llm-d-sc routing traces</h1>
  <table>
    <thead><tr><th>Started</th><th>Request</th><th>Label</th><th>Route</th><th>Score</th><th>Status</th><th>ms</th></tr></thead>
    <tbody>{body}</tbody>
  </table>
</body>
</html>
"""
    return page.encode()


class Handler(BaseHTTPRequestHandler):
    server_version = "llm-d-sc-trace-ui/1"

    def log_message(self, format_string, *args):
        print(json.dumps({"event": "http", "message": format_string % args}), flush=True)

    def send_bytes(self, status: int, content_type: str, body: bytes,
                   extra_headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.send_bytes(200, "text/html; charset=utf-8", dashboard(traces()))
            return
        if self.path == "/_trace/api/traces":
            body = json.dumps({"traces": traces()}, separators=(",", ":")).encode()
            self.send_bytes(200, "application/json", body)
            return
        self.relay("GET")

    def do_POST(self):
        self.relay("POST")

    def do_DELETE(self):
        if self.path == "/_trace/api/traces":
            clear_traces()
            self.send_bytes(200, "application/json", b'{"status":"cleared"}')
            return
        self.relay("DELETE")

    def do_PUT(self):
        self.relay("PUT")

    def do_PATCH(self):
        self.relay("PATCH")

    def relay(self, method: str):
        trace_id = uuid.uuid4().hex
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        question = question_from(body) if self.path.startswith("/v1/chat/completions") else None
        if self.server.route is None:
            create_trace(trace_id, method, self.path, question)
        started = time.monotonic()
        headers = {
            key: value for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP
        }
        request = Request(
            self.server.upstream + self.path,
            data=body if method != "GET" else None,
            headers=headers,
            method=method,
        )
        try:
            with urlopen(request, timeout=600) as response:
                response_body = response.read()
                response_headers = {
                    key: value for key, value in response.headers.items()
                    if key.lower() not in HOP_BY_HOP
                }
                if self.server.route is not None:
                    response_headers["X-Demo-Route"] = self.server.route
                    classification = self.headers.get("X-Llm-D-Sc-Label")
                    if classification:
                        response_headers["X-Demo-Classification"] = classification
                else:
                    complete_trace(trace_id, response.status, response_headers,
                                   int((time.monotonic() - started) * 1000))
                self.send_response(response.status)
                for key, value in response_headers.items():
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(response_body)))
                self.end_headers()
                self.wfile.write(response_body)
        except HTTPError as error:
            response_body = error.read()
            if self.server.route is None:
                complete_trace(trace_id, error.code, error.headers,
                               int((time.monotonic() - started) * 1000), str(error))
            self.send_bytes(error.code, error.headers.get_content_type(),
                            response_body)
        except (OSError, URLError) as error:
            if self.server.route is None:
                complete_trace(trace_id, None, {},
                               int((time.monotonic() - started) * 1000), str(error))
            self.send_bytes(502, "application/json",
                            json.dumps({"error": "upstream unavailable"}).encode())


class RelayServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], upstream: str,
                 route: str | None = None):
        super().__init__(address, Handler)
        self.upstream = upstream
        self.route = route


if __name__ == "__main__":
    if not __debug__ or os.environ.get("PYTHONOPTIMIZE"):
        raise SystemExit("Run without Python -O/PYTHONOPTIMIZE")
    with connection():
        pass
    for port, upstream, route in (
        (8081, CPU_UPSTREAM, "vllm-cpu"),
        (8082, GPU_UPSTREAM, "vllm-gpu"),
    ):
        threading.Thread(
            target=RelayServer(("0.0.0.0", port), upstream, route).serve_forever,
            daemon=True,
        ).start()
    RelayServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), UPSTREAM).serve_forever()
