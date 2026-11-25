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
    groups = catalog.guide_index()
    assert any(group["id"] == "Vault-Recovery" for group in groups)
    for language in ("en", "pl", "es", "de", "ru"):
        assert catalog.resources.ui[language]["guide.source.Vault-Recovery"] == "Vault"
    for number in (65, 73, 83, 93):
        hints = catalog.quests[number]["hints"]
        assert hints[0].get("guide") == "vault-recovery"
        published = catalog.public(number, hints=3)["hints"]
        for hint, rendered in zip(hints, published, strict=True):
            if "guide" in hint:
                expected = f"guide/{hint['guide']}"
                if "section" in hint:
                    authored_guide = catalog.guide(hint["guide"])
                    expected = f"guides#guide={authored_guide['id']}&section={hint['section']}"
                assert rendered["url"] == expected
            elif "url" in hint:
                assert rendered["url"] == hint["url"] and rendered["url"].startswith("https://")
            else:
                assert "url" not in rendered
                assert all(
                    any(3 <= sum(bool(line.strip()) for line in block.splitlines()[1:-1]) <= 5
                        for block in fenced_blocks(text))
                    for text in rendered["text"].values()
                )
        urls = [hint["url"] for hint in published if "url" in hint]
        assert len(set(urls)) == len(urls)
    russian = (ROOT / "docs/Vault-Recovery.md").read_text()
    assert russian == catalog.guide_messages["vault-recovery"]["ru"]["text"]
    english = catalog.guide_messages["vault-recovery"]["en"]["text"]
    assert hashlib.sha256(english.encode()).hexdigest() == guide["source_hash"]
    for language in ("en", "pl", "es", "de", "ru"):
        text = guide["content"][language]
        assert "/v1/sys/unseal" in text
        assert "$VAULT_ADDR/v1/$KV_API_PATH" in text
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
    standalone = catalog.script(65, 0, "check")
    individual = [
        "set -euo pipefail\ncd ~/quest\n" + goal["check"]
        for goal in catalog.quests[65]["stages"][0]["objectives"]
    ]
    for checks in ([standalone], individual):
        results = [
            subprocess.run(["bash", "-c", check], capture_output=True, text=True)
            for check in checks
        ]
        assert all(result.returncode != 0 for result in results)
        stdout = "".join(result.stdout for result in results)
        stderr = "".join(result.stderr for result in results)
        assert len(stdout.splitlines()) == 10
        assert not stderr
        for secret in ("fixture-token-private", "fixture-share-private", "fixture-value-private"):
            assert secret not in stdout + stderr



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
        # Choose authorized inputs explicitly; the guide does not supply the diagnosis.
        if number == 83:
            runtime.exec(run, (ROOT / "solutions/083/0.sh").read_text(), timeout=180)
        prefix = (
            "set -euo pipefail\ncd ~/quest\nsource platform.env\n"
            "export RECOVERY_SHARES=unseal-shares.json KV_API_PATH=secret/data/dispatch\n"
            "export READER_TOKEN_FILE=guide-reader APPLICATION_URL=http://127.0.0.1:18081\n"
            'umask 077; printf %s "$VAULT_READER_TOKEN" > guide-reader\n'
        )
        for index in ((0, 1) if number == 65 else (1, 2)):
            command = "\n".join(examples[index].splitlines()[1:-1])
            result = runtime.exec(run, prefix + command, timeout=240)
            assert "north-secret" not in result.stdout
        # Source-only examples cannot replace consumer recovery.
        result = runtime.exec(run, catalog.script(number, 0, "check"), check=False, timeout=60)
        assert (result.returncode == 0) is (number == 83), result.stderr + "\n" + result.stdout
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
    # This fixture models the original seal/share/read predicates, not the new
    # backend-frozen application identities. Retain each original negative whole.
    checks = []
    for goal in catalog.quests[65]["stages"][0]["objectives"]:
        check = goal["check"]
        if "<<'DQ_LEGACY'\n" in check:
            check = check.split("<<'DQ_LEGACY'\n", 1)[1].split("\nDQ_LEGACY", 1)[0]
        checks.append(check)
    standalone = "set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n"
    standalone += "".join("(\nset -e\n" + c + "\n)\n[ $? -eq 0 ] || failed=1\n" for c in checks)
    standalone += 'exit "$failed"\n'
    individual = ["set -euo pipefail\ncd ~/quest\n" + c for c in checks]
    for checks in ([standalone], individual):
        results = [
            subprocess.run(["bash", "-c", check], capture_output=True, text=True)
            for check in checks
        ]
        assert sum(result.returncode != 0 for result in results) == 1
        if len(results) > 1:
            assert [result.returncode for result in results] == [0, 1, 0]
        stdout = "".join(result.stdout for result in results)
        stderr = "".join(result.stderr for result in results)
        assert len(stdout.splitlines()) == 1
        assert "[0] ≠ [1]" in stdout
        assert "fixture-share-private" not in stdout + stderr
