"""Vault exercise exports only allowlisted denial metadata."""

import json

from devops_quests.platform import Platform


def test_audit_metadata_excludes_tokens_values_and_arbitrary_error_text():
    request = {
        "id": "12345678-1234-1234-1234-123456789abc",
        "path": "secret/data/dispatch",
        "operation": "read",
        "client_token": "fixture-token-canary",
        "data": {"value": "private-canary"},
    }
    raw = [
        {"type": "request", "request": request},
        {
            "type": "response",
            "request": request,
            "error": "denied error-text-canary",
            "auth": {"token": "root-canary"},
        },
        {
            "type": "response",
            "request": dict(request, path="sys/audit"),
            "error": "denied",
        },
    ]
    result = Platform.audit_denials("\n".join(json.dumps(e) for e in raw))
    assert result == [
        {
            "request_id": request["id"],
            "path": "secret/data/dispatch",
            "operation": "read",
            "reason": "permission_denied",
        }
    ]
    assert "canary" not in json.dumps(result)
