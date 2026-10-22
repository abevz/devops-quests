"""Game token renewal stays bounded and never exposes initialization authority."""

import json
import subprocess

import pytest

from devops_quests.platform import Platform


@pytest.mark.parametrize("level", [44, 48, 65, 93, 99])
def test_renewal_capability_is_scoped_to_the_requested_game(
    tmp_path, monkeypatch, level
):
    class FixtureRuntime:
        state = tmp_path

        def __init__(self):
            self.commands = []
            self.token_count = 0

        def docker(self, *args, input=None):
            self.commands.append((args, input))
            if "operator" in args and "init" in args:
                data = {
                    "root_token": "fixture-root-authority",
                    "unseal_keys_b64": ["fixture-share-a", "fixture-share-b"],
                }
            elif "token" in args and "create" in args:
                self.token_count += 1
                data = {"auth": {"client_token": f"fixture-token-{self.token_count}"}}
            elif "token" in args and "lookup" in args:
                data = {"data": {"accessor": "fixture-compromised-accessor"}}
            elif "status" in args:
                data = {"cluster_id": "fixture-existing-cluster"}
            else:
                return subprocess.CompletedProcess([], 0, "", "")
            return subprocess.CompletedProcess([], 0, json.dumps(data), "")

        def exec(self, *args, **kwargs):
            return subprocess.CompletedProcess([], 0, "", "")

    run = {"id": "renewal-fixture", "level": level}
    (tmp_path / "bays" / run["id"]).mkdir(parents=True)
    runtime = FixtureRuntime()
    platform = Platform(runtime)
    written = {}
    monkeypatch.setattr(platform, "container", lambda *a, **k: "owned-vault")
    monkeypatch.setattr(platform, "wait", lambda *a, **k: None)
    monkeypatch.setattr(
        platform, "put", lambda run, name, content: written.update({name: content})
    )
    environment = platform.vault(run)

    assert environment["VAULT_READER_TOKEN"] == "fixture-token-1"
    assert environment["VAULT_MANAGER_TOKEN"] == "fixture-token-2"
    assert all("fixture-root-authority" not in text for text in written.values())
    if level in {65, 93}:
        assert json.loads(written["unseal-shares.json"]) == [
            "fixture-share-a",
            "fixture-share-b",
        ]
        assert any("seal" in args for args, _ in runtime.commands)
    else:
        assert all("fixture-share-" not in text for text in written.values())
    private = tmp_path / "bays" / run["id"] / "vault-init.json"
    assert private.stat().st_mode & 0o777 == 0o600

    roles = [
        args for args, _ in runtime.commands if "auth/token/roles/rail-station" in args
    ]
    manager = [
        content
        for args, content in runtime.commands
        if "rail-manager" in args and "policy" in args
    ][-1]
    if level == 48:
        assert "sys/policies/acl/rail-reader" not in manager
        assert len(roles) == 1
        assert "allowed_policies=rail-reader" in roles[0]
        assert "token_explicit_max_ttl=600" in roles[0]
        assert "renewable=true" in roles[0]
        issuer = json.loads(manager)["path"]
        assert set(issuer) == {"auth/token/create/rail-station"}
        scope = issuer["auth/token/create/rail-station"]
        assert scope["capabilities"] == ["update"]
        assert scope["allowed_parameters"]["ttl"] == ["60s"]
        assert "ttl" in scope["required_parameters"]
        assert written["station-token"] == environment["VAULT_READER_TOKEN"]
        assert "VAULT_READER_TOKEN=$(cat station-token)" in written["sync-secret.sh"]
        assert any(
            "-ttl=45s" in args and "-explicit-max-ttl=600s" in args
            for args, _ in runtime.commands
        )
    elif level == 44:
        assert 'path "sys/policies/acl/rail-reader"' in manager
        assert roles == []
        assert "auth/token/create" not in manager
        assert "station-token" not in written
        assert "cat station-token" not in written["sync-secret.sh"]
    elif level == 99:
        scope = json.loads(manager)["path"]
        assert set(scope) == {
            "auth/token/create/rail-rotation",
            "auth/token/revoke-accessor",
        }
        assert scope["auth/token/create/rail-rotation"]["allowed_parameters"] == {
            "policies": ["rail-reader"],
            "ttl": ["300s"],
            "renewable": [False],
            "explicit_max_ttl": ["600s"],
        }
        assert scope["auth/token/revoke-accessor"]["allowed_parameters"] == {
            "accessor": ["fixture-compromised-accessor"]
        }
        assert written["compromised-accessor"] == "fixture-compromised-accessor"
        assert "station-token" not in written
        assert "cat station-token" in written["sync-secret.sh"]
    else:
        assert manager == 'path "secret/data/dispatch" { capabilities = ["deny"] }\n'
        assert roles == []
        assert 'path "secret/data/dispatch"' in written["reader.hcl"]
        if level == 93:
            assert written["original-cluster-id"] == "fixture-existing-cluster"
    assert 'path "*"' not in manager
