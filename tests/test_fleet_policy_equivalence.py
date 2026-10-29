"""Fleet checks accept safe task forms without accepting faked convergence."""

import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


@pytest.fixture
def play():
    return [{
        "hosts": "fleet",
        "handlers": [{"name": "Reload banner", "command": "dq-service reload"}],
        "tasks": [
            {"copy": {"dest": "/srv/site/message", "content": "north-79\n", "mode": "644"}, "notify": ["Reload banner"]},
            {"file": {"path": "/srv/site/config", "state": "directory", "mode": "755"}},
            {"copy": {"dest": "/srv/site/config/route", "content": "route=north\n", "mode": "644"}},
        ],
    }]


def run_fleet_probe(tmp_path, data):
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(data))
    source = (ROOT / "quests/079/check-0.sh").read_text()
    code = source.split("<<'DQ_FLEET'\n", 1)[1].split("\nDQ_FLEET\n", 1)[0]
    return subprocess.run([sys.executable, "-"], input=code, cwd=tmp_path, capture_output=True, text=True)


def test_aliases_notification_list_and_safe_task_order_are_accepted(tmp_path, play):
    assert run_fleet_probe(tmp_path, play).returncode == 0


@pytest.mark.parametrize("change", ["changed_when", "missing_handler", "wrong_mode", "route_before_directory", "extra_task_action", "extra_handler"])
def test_faked_convergence_or_missing_contract_is_rejected(tmp_path, play, change):
    if change == "changed_when":
        play[0]["tasks"][0]["changed_when"] = False
    elif change == "missing_handler":
        play[0]["handlers"] = []
    elif change == "wrong_mode":
        play[0]["tasks"][2]["copy"]["mode"] = "600"
    elif change == "route_before_directory":
        play[0]["tasks"][1], play[0]["tasks"][2] = play[0]["tasks"][2], play[0]["tasks"][1]
    elif change == "extra_task_action":
        play[0]["tasks"][0]["shell"] = "echo unexpected"
    else:
        play[0]["handlers"].append({"name": "extra", "listen": "Reload banner", "command": "echo unexpected"})
    result = run_fleet_probe(tmp_path, play)
    assert result.returncode != 0
    assert result.stdout.strip()
