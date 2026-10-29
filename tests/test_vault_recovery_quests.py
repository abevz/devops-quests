"""Safety and feedback contracts for the disposable Vault recovery quests."""

import hashlib
import os
import shutil
import subprocess

import pytest

from devops_quests.catalog import Catalog, ROOT
from devops_quests.code_translation import fenced_blocks


def test_vault_quests_link_an_authored_localized_recovery_guide():
    catalog = Catalog()
    guide = catalog.guide("vault-recovery")
    for number in (65, 83, 93):
        assert all(hint.get("guide") == "vault-recovery" for hint in catalog.quests[number]["hints"])
    russian = (ROOT / "docs/Vault-Recovery.md").read_text()
    assert russian == catalog.guide_messages["vault-recovery"]["ru"]["text"]
    assert hashlib.sha256(russian.encode()).hexdigest() == guide["source_hash"]
    for language in ("en", "pl", "es", "de", "ru"):
        text = guide["content"][language]
        assert "/v1/sys/unseal" in text
        assert "/v1/secret/data/dispatch" in text
        assert "sync-secret.sh" in text
        assert fenced_blocks(text) == fenced_blocks(guide["content"]["en"])


@pytest.mark.skipif(not shutil.which("jq"), reason="jq is needed for the Vault JSON checks")
def test_065_reports_failed_conditions_without_disclosing_fixture_secrets(tmp_path, monkeypatch):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "platform.env").write_text(
        'VAULT_ADDR="http://fixture.invalid"\nVAULT_READER_TOKEN="fixture-token-private"\n'
    )
    shares = quest / "unseal-shares.json"
    shares.write_text('["fixture-share-private"]\n')
    shares.chmod(0o644)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    curl = bin_dir / "curl"
    curl.write_text(
        "#!/bin/bash\n"
        'case "$*" in\n'
        "  *sys/seal-status*) echo '{\"initialized\":false,\"sealed\":true,\"t\":1,\"n\":2}' ;;\n"
        "  *) echo '{\"data\":{\"data\":{\"value\":\"fixture-value-private\"}}}' ;;\n"
        "esac\n"
    )
    curl.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    catalog = Catalog()
    checks = (
        catalog.script(65, 0, "check"),
        catalog.quests[65]["stages"][0]["objectives"][0]["check"],
    )
    for check in checks:
        result = subprocess.run(["bash", "-c", check], capture_output=True, text=True)
        assert result.returncode != 0
        assert len(result.stdout.splitlines()) == 8
        assert not result.stderr
        for secret in ("fixture-token-private", "fixture-share-private", "fixture-value-private"):
            assert secret not in result.stdout


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Explicit isolated sandbox opt-in required",
)
@pytest.mark.parametrize(("number", "blocks"), [(65, (0, 1)), (83, (2, 1))])
def test_vault_guide_examples_in_disposable_bay(number, blocks):
    import secrets

    from devops_quests.runtime import Runtime

    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    try:
        runtime.create(run)
        runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + catalog.script(number, 0, "setup"), timeout=240)
        examples = fenced_blocks(catalog.guide("vault-recovery")["content"]["en"])
        for index in blocks:
            command = "\n".join(examples[index].splitlines()[1:-1])
            result = runtime.exec(run, command, timeout=240)
            assert "north-secret" not in result.stdout
        result = runtime.exec(run, catalog.script(number, 0, "check"), check=False, timeout=60)
        assert result.returncode == 0, result.stderr + "\n" + result.stdout
    finally:
        runtime.teardown(run)


@pytest.mark.skipif(not shutil.which("jq"), reason="jq is needed for the Vault JSON example")
def test_vault_guide_read_fails_when_the_http_request_fails(tmp_path, monkeypatch):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "platform.env").write_text(
        'VAULT_ADDR="http://fixture.invalid"\nVAULT_READER_TOKEN="fixture-token-private"\n'
    )
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    curl = bin_dir / "curl"
    curl.write_text("#!/bin/bash\nexit 22\n")
    curl.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    example = fenced_blocks(Catalog().guide("vault-recovery")["content"]["en"])[1]
    command = "\n".join(example.splitlines()[1:-1])
    result = subprocess.run(["bash", "-c", command], capture_output=True, text=True)
    assert result.returncode != 0
    assert "OK" not in result.stdout
    assert "fixture-token-private" not in result.stdout + result.stderr


def test_vault_guide_policy_example_does_not_write_outside_quest(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    example = fenced_blocks(Catalog().guide("vault-recovery")["content"]["en"])[2]
    command = "\n".join(example.splitlines()[1:-1])
    result = subprocess.run(["bash", "-c", command], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode != 0
    assert not (tmp_path / "reader.hcl").exists()


@pytest.mark.skipif(not shutil.which("jq"), reason="jq is needed for the Vault JSON checks")
def test_065_rejects_duplicate_shares_and_keeps_token_out_of_curl_arguments(tmp_path, monkeypatch):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "platform.env").write_text(
        'VAULT_ADDR="http://fixture.invalid"\nVAULT_READER_TOKEN="fixture-token-private"\n'
    )
    shares = quest / "unseal-shares.json"
    shares.write_text('["fixture-share-private", "fixture-share-private"]\n')
    shares.chmod(0o600)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    curl = bin_dir / "curl"
    curl.write_text(
        "#!/bin/bash\n"
        '[[ "$*" != *fixture-token-private* ]] || exit 77\n'
        'case "$*" in\n'
        "  *sys/seal-status*) echo '{\"initialized\":true,\"sealed\":false,\"t\":2,\"n\":3}' ;;\n"
        "  *) echo '{\"data\":{\"data\":{\"value\":\"north-secret\"}}}' ;;\n"
        "esac\n"
    )
    curl.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    catalog = Catalog()
    for check in (
        catalog.script(65, 0, "check"),
        catalog.quests[65]["stages"][0]["objectives"][0]["check"],
    ):
        result = subprocess.run(["bash", "-c", check], capture_output=True, text=True)
        assert result.returncode != 0
        assert len(result.stdout.splitlines()) == 1
        assert "[0] ≠ [1]" in result.stdout
        assert "fixture-share-private" not in result.stdout + result.stderr
