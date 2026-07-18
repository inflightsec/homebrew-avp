#!/usr/bin/env python3
"""Tiny hermetic HTTP echo server for the Homebrew end-to-end smoke.

Listens on 127.0.0.1:<port> (default 8080) and answers every request with a
JSON body echoing the request method, path, and received headers. The smoke
asserts the REAL secret value shows up in the echoed Authorization header
(proving the proxy substituted the placeholder on the wire) and that the
placeholder itself does not. Stdlib only — no third-party dependency.
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080


class Echo(BaseHTTPRequestHandler):
    def _reply(self) -> None:
        body = json.dumps(
            {
                "method": self.command,
                "path": self.path,
                "headers": {k: v for k, v in self.headers.items()},
            }
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = _reply
    do_POST = _reply

    def log_message(self, *args: object) -> None:  # keep CI logs quiet
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Echo).serve_forever()
