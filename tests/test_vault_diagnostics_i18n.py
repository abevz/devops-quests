"""Vault check failures are visible in every supported reading language."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import Catalog, ROOT


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.mark.parametrize(
    ("number", "stage", "expected"),
    [(44, 0, 7), (65, 0, 10), (83, 0, 4), (93, 0, 1), (93, 1, 8)],
)
def test_vault_failure_lines_are_localized(tmp_path, catalog, number, stage, expected):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    (quest / "platform.env").write_text(
        "export VAULT_ADDR=http://unused VAULT_READER_TOKEN=synthetic-reader VAULT_MANAGER_TOKEN=synthetic-manager\n"
    )
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("curl", "kubectl"):
        binary = binaries / name
        binary.write_text("#!/bin/sh\nexit 1\n")
        binary.chmod(0o755)
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    assert source == catalog.quests[number]["stages"][stage]["objectives"][0]["check"]
    env = {**os.environ, "HOME": str(home), "PATH": f"{binaries}:{os.environ['PATH']}"}
    result = subprocess.run(
        ["bash", "-c", source], text=True, capture_output=True, env=env, timeout=20
    )
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == expected, (
        result.stdout + result.stderr
    )
    assert len(result.stdout.encode()) <= 2000
    expected_markers = {
        (44, 0): {
            "policy_read",
            "policy_scope",
            "reader",
            "cap_secret_data_dispatch",
            "cap_secret_data_wrong",
            "cap_secret_data_other",
            "cap_sys_mounts",
        },
        (65, 0): {
            "initialized",
            "sealed",
            "threshold",
            "shares",
            "mode",
            "array",
            "length",
            "types",
            "distinct",
            "reader",
        },
        (83, 0): {"reader", "secret", "env", "rollout"},
        (93, 0): {"init"},
        (93, 1): {
            "initialized",
            "sealed",
            "cluster",
            "threshold",
            "shares",
            "reader",
            "manager",
            "mode",
        },
    }
    assert set(markers) == expected_markers[(number, stage)]
    for marker in markers:
        assert set(catalog.public(number)["diagnostics"][marker]) >= {
            "en",
            "pl",
            "es",
            "de",
            "ru",
        }
