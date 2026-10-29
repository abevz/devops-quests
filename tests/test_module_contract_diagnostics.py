"""Exercise the interactive and standalone diagnostic paths for quest 003."""

import os
import subprocess

import pytest

from devops_quests.catalog import Catalog, ROOT
from devops_quests.engine import Engine
from devops_quests.store import Store


@pytest.fixture
def module_probe(tmp_path, monkeypatch):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "north.txt").write_text("north-ready\n")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tofu = bin_dir / "tofu"
    tofu.write_text(
        "#!/bin/bash\n"
        'case "$1" in\n'
        '  state) [[ "$FAIL_CONDITION" == state ]] || echo module.notice.local_file.notice ;;\n'
        '  output) if [[ "$FAIL_CONDITION" == output ]]; then echo wrong; else echo north-ready; fi ;;\n'
        '  plan) [[ "$FAIL_CONDITION" != plan ]] || exit 2 ;;\n'
        "esac\n"
    )
    tofu.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("FAIL_CONDITION", "")
    return quest


@pytest.mark.parametrize("condition", ["state", "file", "output", "plan"])
def test_each_003_failure_has_one_diagnostic_in_both_entrypoints(
    module_probe, monkeypatch, condition
):
    monkeypatch.setenv("FAIL_CONDITION", condition)
    if condition == "file":
        (module_probe / "north.txt").write_text("wrong\n")
    catalog = Catalog()
    standalone = catalog.script(3, 0, "check")
    objective = catalog.quests[3]["stages"][0]["objectives"][0]["check"]
    for check in (standalone, objective):
        result = subprocess.run(["bash", "-c", check], capture_output=True, text=True)
        assert result.returncode != 0
        assert len(result.stdout.splitlines()) == 1
        assert result.stderr == ""


async def test_003_diagnostic_reaches_final_check_feedback(module_probe, monkeypatch, tmp_path):
    monkeypatch.setenv("FAIL_CONDITION", "state")
    store = Store(tmp_path / "progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "fixture")
    run = store.create_run(store.session(token)["user_id"], 3, "normal")

    class Runtime:
        def exec(self, _run, script, **_kwargs):
            return subprocess.run(["bash", "-c", script], capture_output=True, text=True)

    result = await Engine(store, Catalog(ROOT), Runtime()).poll(run, final=True)
    detail = result["check_result"]["remaining"][0]["detail"]
    assert "module.notice.local_file.notice" in detail
    assert len(detail.splitlines()) == 1


@pytest.mark.parametrize(
    ("number", "address"),
    [(26, "docker_container.worker"), (84, "module.station.docker_container.worker")],
)
def test_container_checks_reject_a_different_state_id(
    tmp_path, monkeypatch, number, address
):
    import shutil

    if not shutil.which("jq"):
        pytest.skip("jq is needed to inspect the state JSON")
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "original-id").write_text("live-id\n")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tofu = bin_dir / "tofu"
    tofu.write_text(
        "#!/bin/bash\n"
        'case "$1" in\n'
        '  state) printf "%s\\n" "$STATE_ADDRESS" ;;\n'
        '  show) printf "%s\\n" "$STATE_JSON" ;;\n'
        '  output) printf "%s\\n" live-id ;;\n'
        '  plan) exit 0 ;;\n'
        "esac\n"
    )
    tofu.chmod(0o755)
    docker = bin_dir / "docker"
    docker.write_text(
        "#!/bin/bash\n"
        'if [[ "$3" == --format ]]; then echo live-id; '
        'else echo \'[{"State":{"Running":true,"Paused":false}}]\'; fi\n'
    )
    docker.chmod(0o755)
    import json

    resource = {"address": address, "values": {"id": "different-id"}}
    module = (
        {"resources": [resource]}
        if number == 26
        else {"child_modules": [{"address": "module.station", "resources": [resource]}]}
    )
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(bin_dir) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("STATE_ADDRESS", address)
    monkeypatch.setenv("STATE_JSON", json.dumps({"values": {"root_module": module}}))
    catalog = Catalog()
    checks = (
        catalog.script(number, 0, "check"),
        catalog.quests[number]["stages"][0]["objectives"][0]["check"],
    )
    for check in checks:
        result = subprocess.run(["bash", "-c", check], capture_output=True, text=True)
        assert result.returncode != 0
        assert len(result.stdout.splitlines()) == 1
        assert "id = original-id" in result.stdout
