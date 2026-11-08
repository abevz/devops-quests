"""Accept result-equivalent fleet programs; do not impose an undeclared task layout."""

import json
import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


def run_goal(tmp_path, number, objective, files=None, body="stable-63"):
    quest = tmp_path / "quest"
    quest.mkdir(exist_ok=True)
    binary = tmp_path / "bin"
    binary.mkdir(exist_ok=True)
    for name, value in (files or {}).items():
        (quest / name).write_text(value)
    # The source can be a role, include, or unrelated harmless layout; this goal observes results.
    if not (quest / "rollout.yml").exists():
        (quest / "rollout.yml").write_text(
            "- hosts: fleet\n  roles: [equivalent_delivery]\n"
        )
    curl = binary / "curl"
    curl.write_text('#!/bin/sh\nprintf "%s\\n" "$DQ_FIXTURE_HTTP"\n')
    curl.chmod(0o755)
    code = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][objective]["check"]
    return subprocess.run(
        ["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + code],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": str(binary) + ":" + os.environ["PATH"],
            "DQ_NAMESPACE": "dq-test",
            "DQ_FIXTURE_HTTP": body,
        },
        text=True,
        capture_output=True,
        timeout=10,
    )


@pytest.mark.parametrize("layout", ["reference", "role", "extra-read-only-task"])
def test_063_healthy_http_is_independent_of_recovery_source_layout(tmp_path, layout):
    result = run_goal(tmp_path, 63, 4, {"rollout.yml": layout})
    assert result.returncode == 0, result.stdout + result.stderr


def test_063_wrong_http_still_fails_with_host_diagnostics(tmp_path):
    result = run_goal(tmp_path, 63, 4, body="candidate")
    assert result.returncode != 0
    for host in (1, 2, 3):
        assert f"[DQ:http_{host}]" in result.stdout


@pytest.mark.parametrize(
    "log,good",
    [
        ("real redacted delivery", True),
        ("another callback format", True),
        ("", False),
        ("game-station-secret-69", False),
    ],
)
def test_069_checks_nonempty_private_record_not_no_log_syntax(tmp_path, log, good):
    result = run_goal(tmp_path, 69, 0, {"deployment.log": log})
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    if not good:
        assert "[DQ:" in result.stdout


def recap(number, variant):
    rows = {
        "app" + str(n): {
            "changed": 1 if number == 74 else 0,
            "skipped": 1 if number == 74 else 0,
            "unreachable": 0,
            "failed": 0,
        }
        for n in (1, 2, 3)
    }
    if variant in {"changed", "skipped"}:
        rows["app2"][variant] = 0 if number == 74 else 1
    elif variant in {"unreachable", "failed"}:
        rows["app2"][variant] = 1
    elif variant == "missing":
        del rows["app3"]
    if variant in {"json", "duplicate-json", "conflicting-alias"}:
        if variant == "conflicting-alias":
            rows["app2"]["failures"] = 1
        text = json.dumps({"stats": rows})
        return (
            text.replace('"failed": 0', '"failed": 1, "failed": 0', 1)
            if variant == "duplicate-json"
            else text
        )
    return "PLAY RECAP ***\n" + "\n".join(
        h + " : " + " ".join(k + "=" + str(v) for k, v in row.items())
        for h, row in rows.items()
    )


@pytest.mark.parametrize(
    "number,objective,path", [(74, 1, "check.log"), (79, 1, "second.log")]
)
@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "json",
        "changed",
        "failed",
        "missing",
        "duplicate-json",
        "conflicting-alias",
    ],
)
def test_recap_results_are_not_tied_to_playbook_structure(
    tmp_path, number, objective, path, variant
):
    result = run_goal(tmp_path, number, objective, {path: recap(number, variant)})
    assert (result.returncode == 0) is (variant in {"reference", "json"}), (
        result.stdout + result.stderr
    )
    assert "Traceback" not in result.stdout + result.stderr
    if result.returncode:
        assert "[DQ:" in result.stdout
