#!/usr/bin/python3
"""A real small service; reload reads the new configuration."""

import http.server
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

PID = Path("/run/quest-service.pid")

if len(sys.argv) > 1 and sys.argv[1] != "serve":
    if sys.argv[1] in ("stop", "restart", "reload") and PID.exists():
        try:
            os.kill(int(PID.read_text()), signal.SIGTERM)
        except ProcessLookupError:
            pass
        PID.unlink(missing_ok=True)
        for _ in range(40):
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", 8080)) != 0:
                    break
            time.sleep(0.05)
    if sys.argv[1] in ("start", "restart", "reload"):
        process = subprocess.Popen(
            [sys.executable, __file__, "serve"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        PID.write_text(str(process.pid))
    sys.exit(0)

message = Path("/srv/site/message").read_bytes()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(message)

    def log_message(self, *_):
        pass


http.server.ThreadingHTTPServer.allow_reuse_address = True
http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
