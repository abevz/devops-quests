"""Real cached consumers and old-minimum regressions for Vault deepening (dq-82)."""
import hashlib
import json
import os
import secrets
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime
from devops_quests.vault_applications import APPLICATION, audit_metadata


def get(url):
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=2) as r:
        return json.load(r)


def wait_for(url, predicate):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            result = get(url)
            if predicate(result):
                return result
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.02)
    raise AssertionError("Application did not reach expected observed state")


@contextmanager
def application(tmp_path, mode, profile):
    # OS chooses a free local port; the child then binds that same endpoint.
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    program = tmp_path / "application.py"
    program.write_text(APPLICATION)
    config = tmp_path / "source.json"
    config.write_text(json.dumps(profile))
    log = tmp_path / "application.log"
    with log.open("w") as output:
        child = subprocess.Popen(
            [sys.executable, "-I", str(program), mode, str(config), str(port)],
            stdout=output, stderr=subprocess.STDOUT,
            env={**os.environ, "HTTP_PROXY": "http://127.0.0.1:1", "NO_PROXY": ""},
        )
        try:
            url = f"http://127.0.0.1:{port}"
            wait_for(url + "/status", lambda _: True)
            yield child, config, url
        finally:
            child.terminate()
            child.wait(timeout=5)


def test_vault_application_requires_deliberate_adoption_and_drops_failed_cache(tmp_path):
    publication = {"value": "secret-value-canary", "version": 1}
    credential = tmp_path / "reader"
    credential.write_text("reader-token-canary")
    credential.chmod(0o600)

    class Vault(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/v1/secret/data/approved" or self.headers.get("X-Vault-Token") != credential.read_text():
                self.send_error(403)
                return
            body = json.dumps({"data": {"data": {"value": publication["value"]},
                                        "metadata": {"version": publication["version"]}}}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Vault)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        profile = {"url": f"http://127.0.0.1:{server.server_port}",
                   "path": "secret/approved", "token_file": str(credential)}
        with application(tmp_path, "vault", profile) as (child, config, url):
            assert get(url + "/status")["status"] == 403
            with pytest.raises(urllib.error.HTTPError) as failure:
                get(url + "/")
            assert failure.value.code == 503
            profile["path"] = "secret/data/approved"
            config.write_text(json.dumps(profile))
            assert get(url + "/status")["ready"] is False
            child.send_signal(signal.SIGHUP)
            observed = wait_for(url + "/status", lambda d: d["ready"])
            assert observed["value_sha256"] == hashlib.sha256(publication["value"].encode()).hexdigest()
            assert observed["version"] == 1
            publication["version"] = 2
            assert get(url + "/")["version"] == 1
            child.send_signal(signal.SIGHUP)
            wait_for(url + "/status", lambda d: d.get("version") == 2)
            profile["path"] = "secret/retired"
            config.write_text(json.dumps(profile))
            child.send_signal(signal.SIGHUP)
            observed = wait_for(url + "/status", lambda d: not d["ready"])
            assert observed["status"] == 403
            assert "value_sha256" not in observed
            assert "canary" not in json.dumps(observed)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    assert "canary" not in (tmp_path / "application.log").read_text()


def test_downstream_does_not_adopt_an_upstream_repair_without_its_own_refresh(tmp_path):
    state = {"ready": False}

    class Upstream(BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps(state).encode()
            self.send_response(200 if state["ready"] else 503)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        profile = {"upstream": f"http://127.0.0.1:{server.server_port}"}
        with application(tmp_path, "upstream", profile) as (child, _, url):
            assert get(url + "/status")["status"] == 503
            state.update(ready=True, version=3, value_sha256="a" * 64)
            assert get(url + "/status")["ready"] is False
            child.send_signal(signal.SIGHUP)
            observed = wait_for(url + "/status", lambda d: d["ready"])
            assert observed["source"] == profile["upstream"]
            assert observed["version"] == 3 and observed["value_sha256"] == "a" * 64
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_consumer_audit_export_discards_secrets_and_unrelated_or_successful_requests():
    request = {"id": "12345678-1234-1234-1234-123456789abc",
               "path": "secret/dispatch", "operation": "read",
               "client_token": "auth-canary", "data": {"value": "value-canary"}}
    event = {"type": "response", "request": request,
             "auth": {"client_token": "root-canary"}, "error": "1 error: permission denied; raw-canary"}
    candidates = [
        event, dict(event, type="request"), dict(event, error=""),
        dict(event, request=dict(request, operation="update")),
        dict(event, request=dict(request, path="sys/audit")),
        dict(event, request=dict(request, id="invalid")),
    ]
    exported = audit_metadata("\n".join(json.dumps(x) for x in candidates))
    assert exported == [{"request_id": request["id"], "path": "secret/dispatch",
                          "operation": "read", "reason": "permission_denied"}]
    assert "canary" not in json.dumps(exported)



# Frozen before deepening: whole references and predicates, including the old complete helper.
OLD_FIXES = {(65, 0): 'set -euo pipefail\ncd ~/quest\nsource platform.env\nfor i in 0 1; do\n jq -n --arg key "$(jq -er ".[$i]" unseal-shares.json)" \'{key:$key}\' > unseal-request.json\n chmod 600 unseal-request.json\n curl -fsS -H \'Content-Type: application/json\' --request PUT --data-binary @unseal-request.json "$VAULT_ADDR/v1/sys/unseal" > unseal-status.json\ndone\nrm unseal-request.json\n', (73, 0): 'set -euo pipefail\ncd ~/quest\njq \'.[0]\' /run/dq/facts/0/audit-events.json > incident.json\ncat > reader.hcl <<\'DQ_ASSET\'\npath "secret/data/dispatch" { capabilities = ["read"] }\nDQ_ASSET\nsource platform.env\njq -n --rawfile policy reader.hcl \'{policy:$policy}\' > reader-policy.json\ncurl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H \'Content-Type: application/json\' --request PUT --data-binary @reader-policy.json "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null\n', (83, 0): 'set -euo pipefail\ncd ~/quest\ncat > reader.hcl <<\'DQ_ASSET\'\npath "secret/data/dispatch" { capabilities = ["read"] }\nDQ_ASSET\nsource platform.env\ncurl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H "Content-Type: application/json" --request PUT --data "$(jq -n --rawfile policy reader.hcl \'{policy:$policy}\')" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null\nbash sync-secret.sh\nkubectl rollout status deployment/relay --timeout=90s\n', (93, 0): 'set -euo pipefail\ncd ~/quest\nprintf \'%s\\n\' \'{"action":"start"}\' > vault-repair.json\n', (93, 1): 'set -euo pipefail\ncd ~/quest\nsource platform.env\nfor i in 0 1; do\n jq -n --arg key "$(jq -er ".[$i]" unseal-shares.json)" \'{key:$key}\' > unseal-request.json\n chmod 600 unseal-request.json\n curl -fsS -H \'Content-Type: application/json\' --request PUT --data-binary @unseal-request.json "$VAULT_ADDR/v1/sys/unseal" > unseal-status.json\ndone\nrm unseal-request.json\n'}

OLD_CHECKS = {(65, 0): 'set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n(\nset -e\nsource platform.env\nstatus=$(curl -fsS "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || true)\nfailed=0\nif ! jq -e \'.initialized == true\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status initialized = true: ✗ [DQ:initialized]\'\n  failed=1\nfi\n\nif ! jq -e \'.sealed == false\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status sealed = false: ✗ [DQ:sealed]\'\n  failed=1\nfi\n\nif ! jq -e \'.t == 2\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status t = 2: ✗ [DQ:threshold]\'\n  failed=1\nfi\n\nif ! jq -e \'.n == 3\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status n = 3: ✗ [DQ:shares]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nfailed=0\nif ! test "$(stat -c %a unseal-shares.json 2>/dev/null)" = 600; then\n  printf \'%s\\n\' \'unseal-shares.json mode = 0600: ✗ [DQ:mode]\'\n  failed=1\nfi\n\nif ! jq -e \'type == "array"\' unseal-shares.json >/dev/null 2>&1; then\n  printf \'%s\\n\' \'unseal-shares.json type = array: ✗ [DQ:array]\'\n  failed=1\nfi\n\nif ! jq -e \'type == "array" and length == 2\' unseal-shares.json >/dev/null 2>&1; then\n  printf \'%s\\n\' \'unseal-shares.json length = 2: ✗ [DQ:length]\'\n  failed=1\nfi\n\nif ! jq -e \'type == "array" and all(.[];type == "string")\' unseal-shares.json >/dev/null 2>&1; then\n  printf \'%s\\n\' \'unseal-shares.json entries type = string: ✗ [DQ:types]\'\n  failed=1\nfi\n\nif ! jq -e \'type == "array" and length == 2 and .[0] != .[1]\' unseal-shares.json >/dev/null 2>&1; then\n  printf \'%s\\n\' \'unseal-shares.json [0] ≠ [1]: ✗ [DQ:distinct]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\numask 077\nheaders=$(mktemp -d)\ntrap \'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"\' EXIT\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_READER_TOKEN" > "$headers/reader"\nfailed=0\nif ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then\n  printf \'%s\\n\' \'reader secret/data/dispatch value = north-secret: ✗ [DQ:reader]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\nexit "$failed"\n', (73, 0): 'set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n(\nset -e\nsource platform.env\njq -e --slurpfile events /run/dq/facts/0/audit-events.json \'keys==["operation","path","reason","request_id"] and .==$events[0][0]\' incident.json >/dev/null\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\ncurl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H \'Content-Type: application/json\' --request POST --data \'{"paths":["secret/data/dispatch","secret/data/other","sys/audit"]}\' "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e \'."secret/data/dispatch"==["read"] and ."secret/data/other"==["deny"] and ."sys/audit"==["deny"]\' >/dev/null\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\ntest "$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)" = north-secret\n)\n[ $? -eq 0 ] || failed=1\nexit "$failed"\n', (83, 0): 'set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n(\nset -e\nsource platform.env\numask 077\nheaders=$(mktemp -d)\ntrap \'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"\' EXIT\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_READER_TOKEN" > "$headers/reader"\nfailed=0\nif ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then\n  printf \'%s\\n\' \'reader secret/data/dispatch value = north-secret: ✗ [DQ:reader]\'\n  failed=1\nfi\n\nif ! test "$(kubectl get secret route-secret -o jsonpath=\'{.data.value}\' 2>/dev/null | base64 -d 2>/dev/null)" = north-secret; then\n  printf \'%s\\n\' \'Secret route-secret value = north-secret: ✗ [DQ:secret]\'\n  failed=1\nfi\n\nif ! test "$(kubectl exec deployment/relay -c worker -- printenv ROUTE_SECRET 2>/dev/null)" = north-secret; then\n  printf \'%s\\n\' \'deployment/relay ROUTE_SECRET = north-secret: ✗ [DQ:env]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nfailed=0\nif ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then\n  printf \'%s\\n\' \'deployment/relay rollout → 0: ✗ [DQ:rollout]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\nexit "$failed"\n', (93, 0): 'set -euo pipefail\ncd ~/quest\nsource platform.env\nif ! curl -fsS "$VAULT_ADDR/v1/sys/init" 2>/dev/null | jq -e \'.initialized == true\' >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/init initialized = true: ✗ [DQ:init]\'\n  exit 1\nfi\n', (93, 1): 'set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n(\nset -e\nsource platform.env\nstatus=$(curl -fsS "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || true)\nfailed=0\nif ! jq -e \'.initialized == true\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status initialized = true: ✗ [DQ:initialized]\'\n  failed=1\nfi\n\nif ! jq -e \'.sealed == false\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status sealed = false: ✗ [DQ:sealed]\'\n  failed=1\nfi\n\nif ! test -s /run/dq/facts/0/original-cluster-id || ! jq -e --arg id "$(cat /run/dq/facts/0/original-cluster-id 2>/dev/null)" \'.cluster_id == $id\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'cluster_id = /run/dq/facts/0/original-cluster-id: ✗ [DQ:cluster]\'\n  failed=1\nfi\n\nif ! jq -e \'.t == 2\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status t = 2: ✗ [DQ:threshold]\'\n  failed=1\nfi\n\nif ! jq -e \'.n == 3\' <<<"$status" >/dev/null 2>&1; then\n  printf \'%s\\n\' \'sys/seal-status n = 3: ✗ [DQ:shares]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\numask 077\nheaders=$(mktemp -d)\ntrap \'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"\' EXIT\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_READER_TOKEN" > "$headers/reader"\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_MANAGER_TOKEN" > "$headers/manager"\nfailed=0\nif ! test "$(curl -fsS -H @"$headers/reader" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null | jq -er .data.data.value 2>/dev/null)" = north-secret; then\n  printf \'%s\\n\' \'reader secret/data/dispatch value = north-secret: ✗ [DQ:reader]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nsource platform.env\numask 077\nheaders=$(mktemp -d)\ntrap \'rm -f "$headers/reader" "$headers/manager"; rmdir "$headers"\' EXIT\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_READER_TOKEN" > "$headers/reader"\nprintf \'X-Vault-Token: %s\\n\' "$VAULT_MANAGER_TOKEN" > "$headers/manager"\nfailed=0\nif ! test "$(curl -sS -o /dev/null -w \'%{http_code}\' -H @"$headers/manager" "$VAULT_ADDR/v1/secret/data/dispatch" 2>/dev/null)" = 403; then\n  printf \'%s\\n\' \'manager secret/data/dispatch HTTP = 403: ✗ [DQ:manager]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\n(\nset -e\nfailed=0\nif ! test "$(stat -c %a unseal-shares.json 2>/dev/null)" = 600; then\n  printf \'%s\\n\' \'unseal-shares.json mode = 0600: ✗ [DQ:mode]\'\n  failed=1\nfi\nexit "$failed"\n)\n[ $? -eq 0 ] || failed=1\nexit "$failed"\n'}

OLD_SYNC = '#!/bin/bash\nset -euo pipefail\ncd ~/quest\nsource platform.env\nvalue=$(curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" "$VAULT_ADDR/v1/secret/data/dispatch" | jq -er .data.data.value)\nkubectl create secret generic route-secret --from-literal=value="$value" --dry-run=client -o yaml | kubectl apply -f -\n'

@pytest.mark.skipif(os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit owned native sandbox opt-in")
@pytest.mark.parametrize("number", [65, 73, 83, 93])
def test_old_vault_minimum_does_not_complete(number, tmp_path):
    import shlex

    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    evidence = {"quest": number, "stages": []}
    def execute(script, check=True):
        return runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + script,
                            check=check, timeout=180)
    try:
        runtime.create(run)
        for stage, item in enumerate(catalog.quests[number]["stages"]):
            execute(catalog.script(number, stage, "setup"))
            runtime.capture_facts(dict(run, stage=stage),
                                  catalog.quests[number].get("immutable", {}).get(stage, []))
            assert execute(catalog.script(number, stage, "check"), False).returncode != 0
            for goal in item["objectives"]:
                if goal.get("keep"):
                    execute(goal["check"])
            if number == 83:
                # Give the frozen old fix its original scaffold as a generous proof.
                execute("printf '%s' " + shlex.quote(OLD_SYNC) + " > sync-secret.sh")
            execute(OLD_FIXES[number, stage])
            if number == 93 and stage == 0:
                runtime.game_controls(run)
            # Establish that every old condition still passes, not just one shortcut.
            execute(OLD_CHECKS[number, stage])
            observed = execute(catalog.script(number, stage, "check"), False)
            if not (number == 93 and stage == 0):
                assert observed.returncode != 0, "Old minimum completed the deepened quest"
            evidence["stages"].append({"stage": stage, "old_whole_check": "PASS",
                                       "current_exit": observed.returncode,
                                       "diagnostics": observed.stdout})
        evidence["result"] = "PASS"
    finally:
        runtime.teardown(run)
        evidence["teardown"] = "PASS"
        destination = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
        destination.mkdir(parents=True, exist_ok=True)
        (destination / f"old-vault-{number:03}.json").write_text(json.dumps(evidence, indent=2) + "\n")
