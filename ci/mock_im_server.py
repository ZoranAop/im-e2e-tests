#!/usr/bin/env python3
# ============================================================
# Mock IM Server (for CI / local self-testing)
# ============================================================
# This stand-in SUT lets the entire test harness (k6 load test +
# shell perf/smoke assertions) run without a real IM deployment.
# It intentionally responds fast and cleanly so that, when the
# harness is correct, the CI gate is GREEN. Pointing IM_HOST at a
# real (slow/failing) SUT will turn the gate RED.
#
# Endpoints:
#   GET  /api/version                 -> {version, nodeIds:[...]}
#   POST /api/message/send            -> {messageUid, ...}   (k6 target)
#   GET  /api/admin/config            -> {config:{...}}
#   GET  /api/admin/square/list       -> {lists:[...]}
#   GET  /api/admin/moments/feeds     -> {feeds:[...]}
#   GET  /api/admin/*                 -> {data:[...]}   (generic admin)
#   *                              -> 200 generic body
#
# Usage:
#   python3 mock_im_server.py [port]        (default 18080)
# ============================================================
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/version":
            self._send(200, {"version": "mock-1.0", "nodeIds": ["im-node-1"]})
        elif path == "/api/admin/config":
            self._send(200, {"config": {"enableConference": True}})
        elif path == "/api/admin/square/list":
            self._send(200, {"lists": [{"id": "mock-list", "name": "mock"}]})
        elif path == "/api/admin/moments/feeds":
            self._send(200, {"feeds": [{"id": "mock-feed", "uid": "mock-uid"}]})
        elif path.startswith("/api/admin/"):
            self._send(200, {"data": [{"id": "mock", "ok": True}]})
        else:
            self._send(200, {"ok": True})

    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0) or 0)
        _ = self.rfile.read(length) if length else b""
        if path == "/api/message/send":
            self._send(200, {"messageUid": "mock-uid-%s" % sys.maxsize, "status": 0})
        else:
            self._send(200, {"ok": True})

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    srv = HTTPServer(("0.0.0.0", port), Handler)
    print("mock-im-server listening on :%d" % port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
