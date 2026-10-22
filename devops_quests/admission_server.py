"""Finite validating webhook for one disposable training namespace."""

import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


def validate(review, namespace):
    if not isinstance(review, dict) or not isinstance(review.get("request"), dict):
        raise TypeError("Invalid AdmissionReview")
    request = review["request"]
    if review.get("apiVersion") != "admission.k8s.io/v1" or not isinstance(
        request.get("uid"), str
    ):
        raise ValueError("Invalid AdmissionReview")
    allowed = True
    if request.get("namespace") == namespace and request.get("name") == "route":
        resource = request.get("resource", {})
        allowed = (
            resource.get("group") == ""
            and resource.get("resource") == "configmaps"
            and request.get("object", {}).get("data", {}).get("route") == "north-121"
        )
    response = {"uid": request["uid"], "allowed": allowed}
    if not allowed:
        response["status"] = {"code": 403, "message": "Station route must be north-121"}
    return {
        "apiVersion": "admission.k8s.io/v1",
        "kind": "AdmissionReview",
        "response": response,
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log admission payloads or headers.

    def do_GET(self):
        self.send_response(200 if self.path == "/ready" else 404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        self.connection.settimeout(2)
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if urlsplit(self.path).path != "/validate" or not 0 < size <= 32768:
                raise ValueError("Invalid request")
            value = validate(
                json.loads(self.rfile.read(size)), os.environ["TRAINING_NAMESPACE"]
            )
        except (ValueError, KeyError, TypeError, TimeoutError):
            self.send_error(400)
            return
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("/webhook/cert.pem", "/webhook/key.pem")
    server = ThreadingHTTPServer(("0.0.0.0", 8443), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
