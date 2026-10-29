"""Registry diagnostics distinguish encoding from credentials without leaking them."""

import base64
import json
import os
import re
import subprocess
import sys

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(
    ("corruption", "expected"),
    [(None, (True, True, True)), ("outer", (False, False, False)), ("auth", (True, False, False)), ("wrong", (True, True, False))],
)
def test_registry_auth_diagnostics_require_canonical_base64(corruption, expected):
    username, password, registry = "reader", "synthetic-password", "registry.invalid"
    content = "reader:wrong-password" if corruption == "wrong" else f"{username}:{password}"
    auth = base64.b64encode(content.encode()).decode()
    if corruption == "auth":
        auth += "$"
    config = json.dumps({"auths": {registry: {"auth": auth}}}).encode()
    outer = base64.b64encode(config).decode()
    if corruption == "outer":
        outer += "$"
    secret = json.dumps({"data": {".dockerconfigjson": outer}})
    source = (ROOT / "quests/042/check-0.sh").read_text()
    programs = re.findall(r"python3 -c '([^']+)'", source)
    assert len(programs) == 3
    outcomes = []
    for program in programs:
        result = subprocess.run(
            [sys.executable, "-c", program],
            input=secret,
            env={**os.environ, "REGISTRY": registry, "REGISTRY_USER": username, "REGISTRY_PASSWORD": password},
            capture_output=True,
            text=True,
            timeout=5,
        )
        outcomes.append(result.returncode == 0)
        assert password not in result.stdout + result.stderr
    assert tuple(outcomes) == expected


@pytest.mark.parametrize(("secret_type", "accepted"), [("kubernetes.io/dockerconfigjson", True), ("Opaque", False)])
def test_registry_secret_type(secret_type, accepted):
    source = (ROOT / "quests/042/check-0.sh").read_text()
    match = re.search(r"check 'registry-pull type = [^']+' '([^']+)'", source)
    assert match is not None
    result = subprocess.run(["jq", "-e", match.group(1)], input=json.dumps({"type": secret_type}), capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is accepted
