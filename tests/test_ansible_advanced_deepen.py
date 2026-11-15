"""Exercise stdin-sensitive checks, actual replay effects and native advanced scenarios."""

import ast
import hashlib
import json
import os
import secrets
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime


def goal(number, index):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]


def programme(number):
    marker = {
        79: "DQ_FLEET_CALLER",
        86: "DQ_PUBLICATION",
        89: "DQ_PUBLICATION",
        96: "DQ_RESTORE_IDENTITY",
    }[number]
    index = {79: 1, 86: 2, 89: 0, 96: 2}[number]
    return (
        goal(number, index)
        .split("<<'" + marker + "'\n", 1)[1]
        .split("\n" + marker, 1)[0]
    )


@pytest.mark.parametrize("index", [2, 3, 4, 5])
@pytest.mark.parametrize("bad_host", [None, "app1", "app2", "app3"])
def test_079_ssh_conditions_run_every_host_through_production_stdin(
    tmp_path, index, bad_host
):
    binary = tmp_path / "bin"
    binary.mkdir()
    temporary = tmp_path / "temporary"
    temporary.mkdir()
    ssh = binary / "ssh"
    ssh.write_text("""#!/usr/bin/python3
import os,sys
from pathlib import Path
if '-n' not in sys.argv:sys.stdin.read()
host=next(arg for arg in sys.argv if arg.startswith('root@')).split('@',1)[1].split('-',1)[0]
with Path(os.environ['TRACE']).open('a') as stream:stream.write(host+'\\n')
if host==os.environ.get('BAD_HOST'):
 print('fixture failure: ✗ [DQ:fixture]');sys.exit(1)
""")
    ssh.chmod(0o755)
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-s"],
        input="set -euo pipefail\n" + goal(79, index),
        env={
            **os.environ,
            "PATH": str(binary) + ":" + os.environ["PATH"],
            "DQ_NAMESPACE": "dq-fixture",
            "TRACE": str(tmp_path / "trace"),
            "BAD_HOST": bad_host or "",
            "TMPDIR": str(temporary),
        },
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert (result.returncode == 0) is (bad_host is None), result.stdout + result.stderr
    assert set((tmp_path / "trace").read_text().splitlines()) == {
        "app1",
        "app2",
        "app3",
    }
    assert not list(temporary.iterdir())


@pytest.mark.parametrize("number", [79, 86, 89, 96])
def test_nested_observer_and_replay_sources_compile(number):
    tree = ast.parse(programme(number))
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Assign)
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in {"observer", "file_observer", "caller_program"}
        ):
            compile(ast.literal_eval(node.value), "nested-shipped-observation", "exec")
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "compile"
            and isinstance(node.args[0], ast.Constant)
        ):
            compile(ast.literal_eval(node.args[0]), "nested-shipped-replay", "exec")


@pytest.mark.parametrize(
    "variant",
    [
        "valid",
        "wrong-cache",
        "lost-control",
        "hidden-write",
        "wrong-mode",
        "failed-cli",
        "timeout",
    ],
)
def test_079_current_program_replay_observes_effects(
    tmp_path, monkeypatch, capsys, variant
):
    monkeypatch.chdir(tmp_path)
    calls = []

    def cli(args, **kwargs):
        assert 0 < kwargs["timeout"] <= 14
        if variant == "timeout":
            raise subprocess.TimeoutExpired(
                args, kwargs["timeout"], output="private-sentinel"
            )
        if variant == "failed-cli":
            return SimpleNamespace(
                returncode=2, stdout="private-sentinel", stderr="private-sentinel"
            )
        inputs = json.loads(args[args.index("-e") + 1])
        inventory = json.loads(Path(args[args.index("-i") + 1]).read_text())
        rows = []
        for name in inventory["all"]["children"]["fleet"]["hosts"]:
            root = Path(
                inputs["delivery_root"].replace("{{ inventory_hostname }}", name)
            )
            (root / "config").mkdir(exist_ok=True)
            (root / "config").chmod(0o755)
            for path, value in [
                (root / "message", inputs["expected_message"]),
                (root / "config/route", inputs["expected_route"]),
            ]:
                if not path.exists() or path.read_text() != value + "\n":
                    path.write_text(value + "\n")
                path.chmod(0o600 if variant == "wrong-mode" else 0o644)
            cache = root / "cache"
            if variant != "wrong-cache" and (not calls or variant == "hidden-write"):
                cache.write_bytes((root / "message").read_bytes())
            if variant == "lost-control":
                (root / "retained").unlink(missing_ok=True)
            rows.append(
                f"{name} : ok=5 changed={2 if not calls else 0} unreachable=0 failed=0 skipped=0 rescued=0 ignored=0"
            )
        calls.append(args)
        return SimpleNamespace(
            returncode=0, stdout="PLAY RECAP\n" + "\n".join(rows), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", cli)
    with pytest.raises(SystemExit) as result:
        exec(compile(programme(79), "shipped-fleet-replay", "exec"), {})
    assert (result.value.code == 0) is (variant == "valid")
    output = capsys.readouterr().out
    assert "private-sentinel" not in output
    if variant == "timeout":
        assert "[DQ:fleet_budget]" in output


@pytest.fixture(scope="module")
def advanced_catalog():
    return Catalog()


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit native sandbox opt-in"
)
@pytest.mark.parametrize("number", [79, 86, 89, 96])
def test_native_advanced_shortcuts_and_reference(number, advanced_catalog, tmp_path):
    catalog = advanced_catalog
    runtime = Runtime(ROOT / ".state/runtime")
    assert "kubernetes" not in runtime.dependencies({"level": number})
    evidence = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
    evidence.mkdir(parents=True, exist_ok=True)
    fixture = ROOT / "tests/fixtures/deepen-ansible-advanced"
    record = {
        "quest": number,
        "sources": {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for base in (ROOT / f"quests/{number:03}", ROOT / f"solutions/{number:03}")
            for p in base.rglob("*")
            if p.is_file()
        },
        "bays": [],
    }

    def bay(scenario):
        run = {"id": secrets.token_hex(12), "level": number}
        item = {"scenario": scenario, "commands": []}
        record["bays"].append(item)

        def execute(script, expected=0):
            result = runtime.exec(
                run,
                "set -euo pipefail\ncd ~/quest\n" + script,
                check=False,
                timeout=180,
            )
            item["commands"].append(
                {
                    "script": script,
                    "exit": result.returncode,
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                }
            )
            assert result.returncode == expected, result.stdout + result.stderr
            return result

        try:
            runtime.create(run)
            execute(catalog.script(number, 0, "setup"))
            runtime.capture_facts(
                dict(run, stage=0),
                catalog.quests[number].get("immutable", {}).get(0, []),
            )
            for objective in catalog.quests[number]["stages"][0]["objectives"]:
                if objective.get("keep"):
                    execute(objective["check"])
            current = catalog.script(number, 0, "check")
            execute(current, 1)
            if scenario == "old-shortcut":
                if number == 96:
                    execute(
                        "cat > rollout.yml <<'OLD_PROGRAMME'\n"
                        + (fixture / "096-programme.yml").read_text()
                        + "OLD_PROGRAMME\n"
                    )
                execute((fixture / f"{number:03}.sh").read_text())
                execute((fixture / f"{number:03}-legacy-check.sh").read_text())
                failure = execute(current, 1)
                expected_marker = {
                    79: "fleet_effects",
                    86: "application_ready_1",
                    89: "application_ready_1",
                    96: "live_binding_1",
                }[number]
                assert "[DQ:" + expected_marker + "]" in failure.stdout
                if number == 79:
                    assert (
                        "[DQ:http_2]" in failure.stdout
                        and "[DQ:http_3]" in failure.stdout
                    )
                if number == 96:
                    item["result"] = "PASS"
                    return
            execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
            execute(current)
            if number == 96:
                execute(
                    "python3 -I - <<'ALTERNATIVE'\nfrom pathlib import Path\nimport yaml\np=Path('rollout.yml');play=yaml.safe_load(p.read_text());args=play[0]['tasks'][-1]['ansible.builtin.unarchive'];args.pop('include');args['exclude']=['consumer-binding.json','tenant.json'];p.write_text(yaml.safe_dump(play,sort_keys=False))\nALTERNATIVE\nansible-playbook rollout.yml"
                )
                execute(current)
            item["result"] = "PASS"
        finally:
            runtime.teardown(run)
            item["teardown"] = "PASS"

    try:
        bay("old-shortcut")
        if number == 96:
            bay("fresh-reference")
        record["result"] = "PASS"
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        (evidence / f"{number:03}-advanced-native.json").write_text(
            json.dumps(record, indent=2) + "\n"
        )
