"""Stage scripts mirror the ordered production objective checks."""

from pathlib import Path

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
        expected = PRELUDE + "failed=0\n"
        for check in checks:
            expected += "if ! (\n" + check + "\n); then failed=1; fi\n"
        expected += 'exit "$failed"\n'
    assert (path.parent / f"check-{index}.sh").read_text() == expected
