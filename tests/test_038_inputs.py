"""The role override advertised in the briefing exists in a fresh bay."""

import os
import subprocess

import yaml

from devops_quests.catalog import ROOT


def test_038_supplies_an_empty_inventory_override_without_the_answer(tmp_path):
    quest = tmp_path / 'quest'
    quest.mkdir()
    result = subprocess.run(
        ['bash', str(ROOT / 'quests/038/setup-0.sh')], cwd=quest,
        env={**os.environ, 'HOME': str(tmp_path)}, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert yaml.safe_load((quest / 'group_vars/fleet.yml').read_text()) == {}
    assert yaml.safe_load((quest / 'roles/station/defaults/main.yml').read_text()) == {
        'route': 'retired', 'platform': 'shared',
    }
