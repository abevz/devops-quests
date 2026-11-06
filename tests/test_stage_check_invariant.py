"""Stage scripts mirror the ordered production objective checks."""

from pathlib import Path

import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
PRELUDE = "set -euo pipefail\ncd ~/quest\n"
STAGES = [
    (path, index, stage)
    for path in sorted((ROOT / "quests").glob("*/quest.yaml"))
    for index, stage in enumerate(yaml.safe_load(path.read_text())["stages"])
]


@pytest.mark.parametrize("path,index,stage", STAGES, ids=[
    f"{path.parent.name}-{index}" for path, index, _ in STAGES
])
def test_stage_script_matches_objectives(path, index, stage):
    checks = [goal["check"] for goal in stage["objectives"]]
    if len(checks) == 1:
        # Older objectives either include the prelude or rely on the engine's.
        expected = checks[0]
        if not expected.startswith(PRELUDE):
            expected = PRELUDE + expected
        expected = expected.rstrip("\n") + "\n"
    else:
        expected = PRELUDE + "failed=0\nset +e\n"
        for check in checks:
            expected += "(\nset -e\n" + check + "\n)\n[ $? -eq 0 ] || failed=1\n"
        expected += 'exit "$failed"\n'
    assert (path.parent / f"check-{index}.sh").read_text() == expected


@pytest.mark.parametrize("path,index,stage", [
    item for item in STAGES if len(item[2]["objectives"]) > 1
], ids=lambda item: str(item) if isinstance(item, int) else None)
def test_aggregate_catches_intermediate_failure_and_checks_later_goals(
    path, index, stage, tmp_path
):
    script = (path.parent / f"check-{index}.sh").read_text()
    # Substitute the real objective blocks in place; keep the shipped control flow.
    # Longest first prevents one goal's check from matching a prefix in another.
    replacements = []
    for goal, objective in enumerate(stage["objectives"]):
        marker = f"__DQ_TEST_OBJECTIVE_{goal}__"
        replacements.append((objective["check"], marker, goal))
    for check, marker, _ in sorted(replacements, key=lambda item: len(item[0]), reverse=True):
        assert script.count("\n" + check + "\n") == 1
        script = script.replace("\n" + check + "\n", "\n" + marker + "\n")
    script = script.replace("cd ~/quest", f"cd {tmp_path}")
    for _, marker, goal in replacements:
        body = "false\nprintf unreachable\n" if goal == 0 else f"printf '{goal}\n' >> visited\n"
        script = script.replace(marker, body)
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    assert result.returncode == 1
    assert "unreachable" not in result.stdout
    assert (tmp_path / "visited").read_text().splitlines() == [
        str(goal) for goal in range(1, len(stage["objectives"]))
    ]
