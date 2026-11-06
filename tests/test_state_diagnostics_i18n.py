"""State-contract probes name every failed condition in all reading languages."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize(
    ("number", "expected"),
    [
        (3, 4),
        (23, 5),
        (26, 5),
        (29, 4),
        (33, 10),
        (47, 11),
        (71, 8),
        (84, 5),
        (87, 3),
        (92, 8),
    ],
)
def test_missing_contracts_have_translated_diagnostics(
    tmp_path, catalog, number, expected
):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("tofu", "docker"):
        tool = binaries / name
        tool.write_text("#!/bin/sh\nexit 1\n")
        tool.chmod(0o755)
    check = (ROOT / f"quests/{number:03}/check-0.sh").read_text()
    checks = [objective["check"] for objective in catalog.quests[number]["stages"][0]["objectives"]]
    expected_script = "set -euo pipefail\ncd ~/quest\nfailed=0\nset +e\n"
    for objective_check in checks:
        expected_script += "(\nset -e\n" + objective_check + "\n)\n[ $? -eq 0 ] || failed=1\n"
    expected_script += 'exit "$failed"\n'
    assert check == expected_script
    env = {**os.environ, "HOME": str(home), "PATH": f"{binaries}:{os.environ['PATH']}"}
    result = subprocess.run(
        ["bash", "-c", check], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == expected, (
        result.stdout + result.stderr
    )
    assert len(result.stdout.encode()) <= 2000
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
