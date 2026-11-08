"""Check failure handling must retain shell failure semantics and hide Python tracebacks."""

import os
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog


GUARDED = []
for path in sorted((ROOT / "quests").glob("*/quest.yaml")):
    data = yaml.safe_load(path.read_text())
    for stage, value in enumerate(data["stages"]):
        for objective, goal in enumerate(value["objectives"]):
            if "dq_probe_output=$(mktemp)" in goal["check"]:
                GUARDED.append((int(path.parent.name), stage, objective, goal["check"]))


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize(
    "number,stage,objective,source",
    GUARDED,
    ids=[f"{n:03}-{s}-{o}" for n, s, o, _ in GUARDED],
)
def test_python_probe_wrapper_preserves_nonzero_and_has_translated_diagnostic(
    tmp_path, number, stage, objective, source, catalog
):
    prefix, body = source.split("(\nset -euo pipefail\n", 1)
    _, suffix = body.rsplit('\n) >"$dq_probe_output" 2>/dev/null', 1)
    # Execute the real shipped wrapper around a controlled crashing child. In particular,
    # placing the child in an `if` would incorrectly disable errexit inside its subshell.
    program = (
        prefix
        + '(\nset -euo pipefail\npython3 -c "raise ValueError(123)"\nprintf should-not-run\n) >"$dq_probe_output" 2>/dev/null'
        + suffix
    )
    result = subprocess.run(
        ["bash", "-c", program],
        text=True,
        capture_output=True,
        timeout=5,
        env={**os.environ, "TMPDIR": str(tmp_path)},
    )
    assert result.returncode != 0
    assert f"[DQ:probe_{stage}_{objective}]" in result.stdout
    assert "Traceback" not in result.stdout + result.stderr
    assert "should-not-run" not in result.stdout
    assert not list(tmp_path.iterdir()), "Temporary output must be removed on failure"
    diagnostics = catalog.public(number)["diagnostics"]
    assert set(diagnostics[f"probe_{stage}_{objective}"]) >= {
        "en",
        "pl",
        "es",
        "de",
        "ru",
    }


@pytest.mark.parametrize(
    "body,good",
    [
        ("true", True),
        ("test 1 -eq 1 && :", True),
        ("false\ntrue", False),
        ('printf "named: ✗ [DQ:existing]\\n"\nexit 1', False),
    ],
)
def test_check_output_guard_preserves_success_and_existing_markers(
    tmp_path, body, good
):
    _, stage, objective, source = GUARDED[0]
    prefix, old = source.split("(\nset -euo pipefail\n", 1)
    _, suffix = old.rsplit('\n) >"$dq_probe_output" 2>/dev/null', 1)
    result = subprocess.run(
        [
            "bash",
            "-c",
            prefix
            + "(\nset -euo pipefail\n"
            + body
            + '\n) >"$dq_probe_output" 2>/dev/null'
            + suffix,
        ],
        text=True,
        capture_output=True,
        timeout=5,
        env={**os.environ, "TMPDIR": str(tmp_path)},
    )
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    assert not list(tmp_path.iterdir())
    if "existing" in body:
        assert result.stdout.count("[DQ:") == 1


def test_every_embedded_python_check_has_a_failure_boundary():
    for path in (ROOT / "quests").glob("*/quest.yaml"):
        data = yaml.safe_load(path.read_text())
        for stage in data["stages"]:
            for goal in stage["objectives"]:
                code = goal["check"]
                if "python" in code:
                    assert "dq_probe_output=$(mktemp)" in code
