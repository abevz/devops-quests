"""Every prior Ansible diagnostic has translated, host-specific feedback."""

import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT, Catalog


@pytest.mark.parametrize(("number", "stage", "expected"), [(2, 0, 6), (10, 0, 9), (10, 1, 2), (20, 0, 4), (20, 1, 16), (63, 0, 20)])
def test_every_failure_has_a_translated_marker(tmp_path, number, stage, expected):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    for name in ("ssh", "curl", "kubectl", "tofu", "ansible-playbook"):
        program = binaries / name
        program.write_text("#!/bin/bash\nexit 1\n")
        program.chmod(0o755)
    source = (ROOT / f"quests/{number:03}/check-{stage}.sh").read_text()
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "dq-test"}
    result = subprocess.run(["bash", "-c", source], text=True, capture_output=True, env=environment, timeout=15)
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert result.returncode != 0
    assert len(markers) == len(result.stdout.splitlines()) == expected, result.stdout + result.stderr
    assert len(result.stdout) <= 2000
    diagnostics = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(diagnostics[marker]) >= {"en", "pl", "es", "de", "ru"}

def test_host_diagnostics_name_the_specific_machine():
    for quest in (2, 10, 20, 63):
        diagnostics = Catalog().public(quest)['diagnostics']
        for condition in ('content', 'mode', 'http'):
            if condition == 'http' and quest == 2:
                continue
            for host in (1, 2, 3):
                for language in ('en', 'pl', 'es', 'de', 'ru'):
                    assert f'app{host}' in diagnostics[f'{condition}_{host}'][language]
