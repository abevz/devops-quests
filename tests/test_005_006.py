"""Regressions from the owner's 005/006 playtest."""

import os
import re
import subprocess

import pytest
import yaml

from devops_quests.catalog import ROOT


def test_005_setup_removes_the_private_preparation_playbook(tmp_path):
    binaries = tmp_path / "bin"
    binaries.mkdir()
    ansible = binaries / "ansible-playbook"
    ansible.write_text(
        "#!/bin/bash\n"
        'test "$#" = 1 && test "$1" = prepare.yml && test -s prepare.yml\n'
    )
    ansible.chmod(0o755)
    result = subprocess.run(
        ["bash", str(ROOT / "quests/005/setup-0.sh")],
        cwd=tmp_path,
        env={**os.environ, "PATH": f"{binaries}:{os.environ['PATH']}"},
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert not (tmp_path / "prepare.yml").exists()
    rollout = yaml.safe_load((tmp_path / "rollout.yml").read_text())
    assert rollout[0]["hosts"] == "fleet"
    assert rollout[0]["tasks"][0]["ansible.builtin.copy"]["mode"] == "0600"
    quest = yaml.safe_load((ROOT / "quests/005/quest.yaml").read_text())
    assert "prepare.yml" not in quest["facts"]["files"]


@pytest.mark.parametrize("language", ["en", "ru", "de", "es", "pl"])
def test_005_brief_does_not_disclose_the_permission_answer(language):
    values = yaml.safe_load((ROOT / f"quests/005/i18n/{language}.yaml").read_text())
    brief = values["brief"]
    assert not re.search(r"\b0?644\b", values["stages.0.objectives.0.text"])
    assert "prepare.yml" not in brief
    assert not re.search(r"\b0?644\b|\bstat\b", brief)
    commands = re.findall(r"^- `(.*)` —", brief, re.MULTILINE)
    assert len(commands) == 2
    assert all("runuser -u nobody --" in command for command in commands)
    assert any("cat /srv/site/message" in command for command in commands)


@pytest.mark.parametrize("language", ["en", "ru", "de", "es", "pl"])
def test_006_self_verification_observes_the_result_without_the_state_hint(language):
    brief = yaml.safe_load((ROOT / f"quests/006/i18n/{language}.yaml").read_text())["brief"]
    commands = re.findall(r"^- `(.*)` —", brief, re.MULTILINE)
    assert len(commands) == 2
    assert not any("state list" in command or "docker ps" in command for command in commands)
    assert any("docker inspect rail-worker" in command for command in commands)
    assert any("tofu plan" in command and "-detailed-exitcode" in command for command in commands)
