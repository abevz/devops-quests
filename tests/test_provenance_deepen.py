"""Commitment validation and the old provenance-copy shortcut for dq-82/091."""

import hashlib
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

REPORT = {"image": "registry.invalid/parcel@sha256:" + "a" * 64,
          "commit": "b" * 40, "repo": "http://git.invalid/private.git"}


@pytest.mark.parametrize("case", ["correct", "reordered", "image", "commit", "repo", "extra", "missing", "malformed"])
def test_original_provenance_is_bound_without_disclosing_the_tuple(tmp_path, case):
    quest = yaml.safe_load((ROOT / "quests/091/quest.yaml").read_text())
    check = quest["stages"][0]["objectives"][5]["check"]
    code = check.split("<<'DQ_PROVENANCE_COMMITMENT'\n", 1)[1].split("\nDQ_PROVENANCE_COMMITMENT", 1)[0]
    digest = hashlib.sha256(json.dumps(REPORT, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    expected = tmp_path / "commitment.json"
    expected.write_text(json.dumps({"sha256": digest}))
    report = dict(REPORT)
    if case == "reordered":
        report = dict(reversed(list(report.items())))
    elif case in REPORT:
        report[case] = "foreign"
    elif case == "extra":
        report["note"] = "not allowed"
    elif case == "missing":
        del report["repo"]
    candidate = tmp_path / "report.json"
    candidate.write_text("{" if case == "malformed" else json.dumps(report))
    # A learner helper in the working directory must not replace stdlib parsing.
    (tmp_path / "json.py").write_text("raise RuntimeError('untrusted helper')\n")
    result = subprocess.run([sys.executable, "-I", "-", str(expected), str(candidate)],
                            input=code, text=True, cwd=tmp_path, capture_output=True, timeout=5)
    assert (result.returncode == 0) is (case in {"correct", "reordered"})
    assert set(json.loads(expected.read_text())) == {"sha256"}


@pytest.mark.skipif(os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit local sandbox opt-in required")
def test_old_copy_and_report_only_repairs_do_not_complete_provenance():
    catalog = Catalog()
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": 91}
    folder = Path(os.environ.get("DQ_DEEPEN_EVIDENCE", ROOT / "artifacts/provenance-shortcut"))
    folder.mkdir(parents=True, exist_ok=True)
    log = {"quest": 91, "old_source": "ae87ab3"}
    try:
        runtime.create(run)
        runtime.exec(run, catalog.script(91, 0, "setup"), timeout=240)
        runtime.capture_facts(dict(run, stage=0), catalog.quests[91]["immutable"][0])
        check = catalog.script(91, 0, "check")
        assert runtime.exec(run, check, check=False, timeout=60).returncode != 0
        # The old audited minimum was copying either supplied answer tuple.
        for source in ("release-evidence.json", "/run/dq/facts/0/release-evidence.json"):
            runtime.exec(run, "cd ~/quest\ncp " + source + " provenance.json")
            copied = runtime.exec(run, check, check=False, timeout=60)
            assert copied.returncode != 0, "Old copy shortcut solved provenance"
        runtime.exec(run, "cd ~/quest\ntest ! -e source-commit && test ! -e image-ref && test ! -e image-context")
        commitment = runtime.exec(run, "cat /run/dq/facts/0/release-evidence.json").stdout
        assert set(json.loads(commitment)) == {"sha256"}
        # Even a genuinely reconstructed report is insufficient until delivered.
        reference = (ROOT / "solutions/091/0.sh").read_text()
        investigation = reference.split("python3 - <<'PUBLISH_RECORD'", 1)[0]
        runtime.exec(run, investigation, timeout=180)
        verified_report = catalog.quests[91]["stages"][0]["objectives"][5]["check"].split("\n# Deliver the verified record", 1)[0]
        assert runtime.exec(run, "set -euo pipefail\ncd ~/quest\n" + verified_report, check=False, timeout=60).returncode == 0
        after = runtime.exec(run, check, check=False, timeout=60)
        assert after.returncode != 0
        assert "[DQ:provenance_delivery]" in after.stdout
        log.update(old_copy="FAIL as expected", report_only="FAIL as expected",
                   verified_report="PASS", diagnostics=after.stdout)
    except Exception as error:
        log["error"] = str(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            log["teardown"] = "PASS"
        finally:
            (folder / "091.json").write_text(json.dumps(log, indent=2) + "\n")
