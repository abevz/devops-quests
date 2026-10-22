"""The admission contract is finite and has explicit HTTP framing."""

import copy
import http.client
import json
import threading
from http.server import ThreadingHTTPServer

import pytest

from devops_quests.admission_server import Handler, validate


def review(route="north-121"):
    return {
        "apiVersion": "admission.k8s.io/v1",
        "request": {
            "uid": "fixture",
            "namespace": "bay",
            "name": "route",
            "resource": {"group": "", "resource": "configmaps"},
            "object": {"data": {"route": route}},
        },
    }


def test_admission_echoes_uid_allows_valid_route_and_denies_invalid_route():
    assert validate(review(), "bay")["response"] == {"uid": "fixture", "allowed": True}
    denied = validate(review("closed"), "bay")["response"]
    assert (
        denied["uid"] == "fixture"
        and not denied["allowed"]
        and denied["status"]["code"] == 403
    )


def test_admission_does_not_impose_policy_on_foreign_namespaces_or_objects():
    value = review("closed")
    value["request"]["namespace"] = "foreign"
    assert validate(value, "bay")["response"]["allowed"]
    value = review("closed")
    value["request"]["name"] = "unrelated"
    assert validate(value, "bay")["response"]["allowed"]


@pytest.mark.parametrize("change", ["uid", "version", "request"])
def test_invalid_review_is_rejected(change):
    value = copy.deepcopy(review())
    if change == "uid":
        value["request"]["uid"] = None
    if change == "version":
        value["apiVersion"] = "untrusted"
    if change == "request":
        value["request"] = []
    with pytest.raises((ValueError, TypeError)):
        validate(value, "bay")


def test_readiness_has_explicit_empty_body_framing():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        client = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        client.request("GET", "/ready")
        response = client.getresponse()
        assert (
            response.status == 200
            and response.getheader("Content-Length") == "0"
            and response.read() == b""
        )
        client.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


@pytest.mark.parametrize("route,allowed", [("north-121", True), ("closed", False)])
def test_apiserver_timeout_query_is_accepted_without_changing_policy(
    monkeypatch, route, allowed
):
    monkeypatch.setenv("TRAINING_NAMESPACE", "bay")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        client = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        client.request("POST", "/validate?timeout=2s", json.dumps(review(route)))
        response = client.getresponse()
        assert response.status == 200
        assert json.loads(response.read())["response"]["allowed"] is allowed
        client.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
