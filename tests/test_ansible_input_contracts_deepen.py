"""Execute the shipped Ansible capability probes and real old-minimum repairs."""

import copy
import json
import hashlib
import os
import secrets
import re
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime

MARKERS = {
    22: (1, "TEMPLATE_CAPABILITY"),
    55: (0, "PROFILE_SCOPE"),
    58: (0, "ROLE_CAPABILITY"),
}


def program(number):
    index, marker = MARKERS[number]
    check = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())[
        "stages"
    ][0]["objectives"][index]["check"]
    return check.split("<<'DQ_" + marker + "'\n", 1)[1].split("\nDQ_" + marker, 1)[0]


def contract(number):
    if number == 22:
        return {
            "template": "message.j2",
            "cases": {"probe-a": "south", "probe-b": "east", "probe-c": "north"},
        }
    if number == 55:
        return {
            "message": "north-ready",
            "profilePath": "/srv/site/profile.json",
            "profiles": {
                host: {
                    "route": "north-ready",
                    "zone": "east" if host != "app3" else "west",
                    "window": "standby" if host == "app2" else "primary",
                }
                for host in ["app1", "app2", "app3"]
            },
        }
    return {
        "entryRole": "roles/banner",
        "cases": {"first": "south-ready", "second": "east-ready"},
    }


CASES = [
    (22, variant)
    for variant in [
        "valid",
        "reordered-fields",
        "extra-fields",
        "fixed-route",
        "fixed-identity",
        "conflicting-field",
        "render-error",
        "missing-output",
        "slow-command",
        "moderate-command",
        "api-error",
    ]
]
CASES += [
    (55, variant)
    for variant in [
        "valid",
        "extra-profile-fields",
        "serialized-json-order",
        "wrong-scope",
        "lost-defaults",
        "wrong-route-input",
        "wrong-published",
        "missing-published",
        "missing-host",
        "unresolved-input",
        "slow-command",
        "moderate-command",
        "api-error",
    ]
]
CASES += [
    (58, variant)
    for variant in [
        "valid",
        "fixed-route",
        "missing-dependency",
        "changed-again",
        "missing-recap",
        "lost-caller-data",
        "lost-parent-control",
        "missing-output",
        "slow-command",
        "moderate-command",
        "api-error",
    ]
]
GOOD = {
    "valid",
    "reordered-fields",
    "extra-fields",
    "extra-profile-fields",
    "serialized-json-order",
    "moderate-command",
}


@pytest.mark.parametrize("number,variant", CASES)
def test_shipped_ansible_capability_boundaries(number, variant, monkeypatch, capsys):
    code = program(number)
    intent = contract(number)
    real_read = Path.read_text
    elapsed = [0.0]
    calls = [0]

    def read(path, *args, **kwargs):
        return (
            json.dumps(intent)
            if str(path).startswith("/run/dq/facts/0/")
            else real_read(path, *args, **kwargs)
        )

    def cli(args, **kwargs):
        allowed = kwargs["timeout"]
        delay = (
            6
            if variant == "slow-command"
            else 1
            if variant == "moderate-command"
            else 0
        )
        # A single rendering command also needs a deadline counterexample.
        if number == 22 and variant == "slow-command":
            delay = 11
        elapsed[0] += min(delay, allowed)
        if delay > allowed:
            raise subprocess.TimeoutExpired(args, allowed)
        if variant == "api-error":
            return SimpleNamespace(
                returncode=1, stdout="", stderr="private-input-sentinel"
            )
        if args[0] == "ssh":
            host = args[args.index("2222") + 1].split("@", 1)[1].split("-", 1)[0]
            value = copy.deepcopy(intent["profiles"][host])
            if variant == "wrong-published":
                value["zone"] = "retired"
            if variant == "extra-profile-fields":
                value["unrelated"] = "retained"
            return SimpleNamespace(
                returncode=1 if variant == "missing-published" else 0,
                stdout=json.dumps(value),
                stderr="",
            )
        play_path = Path(args[args.index("-i") + 2])
        play = json.loads(real_read(play_path))[0]
        calls[0] += 1
        if number == 22:
            if variant == "render-error":
                return SimpleNamespace(
                    returncode=2, stdout="private-input-sentinel", stderr=""
                )
            dest = play["tasks"][0]["ansible.builtin.template"]["dest"]
            inputs = json.loads(args[args.index("-e") + 1])
            for name, record in inputs["station_routes"].items():
                if variant == "missing-output":
                    continue
                route = "north" if variant == "fixed-route" else record["active"]
                identity = "app1" if variant == "fixed-identity" else name
                lines = ["station=" + identity, "route=" + route]
                if variant == "reordered-fields":
                    lines.reverse()
                if variant == "extra-fields":
                    lines += ["# generated banner", "format=plain"]
                if variant == "conflicting-field":
                    lines += ["route=retired"]
                Path(re.sub(r"{{\s*inventory_hostname\s*}}", name, dest)).write_text(
                    "\n".join(lines) + "\n"
                )
        elif number == 55:
            if variant == "unresolved-input":
                return SimpleNamespace(
                    returncode=2, stdout="private-input-sentinel", stderr=""
                )
            assert kwargs["env"]["ANSIBLE_CONFIG"] == str(Path("ansible.cfg").resolve())
            dest = play["tasks"][0]["ansible.builtin.copy"]["dest"]
            for name, profile in intent["profiles"].items():
                if variant == "missing-host" and name == "app2":
                    continue
                value = {"route": intent["message"], "profile": copy.deepcopy(profile)}
                if variant == "wrong-scope":
                    value["profile"]["window"] = "standby"
                if variant == "lost-defaults":
                    value["profile"].pop("route")
                if variant == "wrong-route-input":
                    value["route"] = "retired"
                if variant == "extra-profile-fields":
                    value["profile"]["unrelated"] = "retained"
                Path(re.sub(r"{{\s*inventory_hostname\s*}}", name, dest)).write_text(
                    json.dumps(value, sort_keys=variant == "serialized-json-order")
                )
        else:
            if variant == "missing-dependency":
                return SimpleNamespace(
                    returncode=2, stdout="private-input-sentinel", stderr=""
                )
            for role in play["roles"]:
                directory = Path(role["install_root"])
                directory.mkdir(exist_ok=True)
                if variant == "lost-parent-control":
                    (directory.parent / "retained-control").unlink(missing_ok=True)
                if variant == "lost-caller-data" and calls[0] == 2:
                    (directory / "keep-existing.txt").unlink(missing_ok=True)
                if variant != "missing-output":
                    (directory / "current").write_text(
                        (
                            "north-ready"
                            if variant == "fixed-route"
                            else role["banner_route"]
                        )
                        + "\n"
                    )
            changed = 4 if calls[0] == 1 else int(variant == "changed-again")
            output = (
                ""
                if variant == "missing-recap"
                else f"PLAY RECAP\nlocalhost : ok=4 changed={changed} unreachable=0 failed=0 skipped=0 rescued=0 ignored=0\n"
            )
            return SimpleNamespace(returncode=0, stdout=output, stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setenv("DQ_NAMESPACE", "dq-synthetic")
    monkeypatch.setattr(Path, "read_text", read)
    monkeypatch.setattr(subprocess, "run", cli)
    monkeypatch.setattr(time, "monotonic", lambda: elapsed[0])
    with pytest.raises(SystemExit) as result:
        exec(compile(code, "shipped-ansible-input-contract", "exec"), {})
    assert bool(result.value.code) == (variant not in GOOD)
    assert elapsed[0] <= 10
    output = capsys.readouterr().out
    assert "private-input-sentinel" not in output
    if number == 58 and variant == "slow-command":
        assert "[DQ:role_budget]" in output
    if number == 58 and variant in {"lost-caller-data", "lost-parent-control"}:
        assert "[DQ:role_preservation]" in output
    if number == 58 and variant == "missing-output":
        assert "[DQ:role_inputs]" in output


@pytest.fixture(scope="module")
def native_contract_catalog():
    return Catalog()


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1", reason="Explicit real sandbox opt-in"
)
@pytest.mark.parametrize("number", [22, 55, 58])
def test_native_ansible_input_shortcuts(number, native_contract_catalog, tmp_path):
    catalog = native_contract_catalog
    runtime = Runtime(ROOT / ".state/runtime")
    run = {"id": secrets.token_hex(12), "level": number}
    folder = Path(os.environ.get("DQ_EVIDENCE_DIR", str(tmp_path)))
    folder.mkdir(parents=True, exist_ok=True)
    record = {
        "quest": number,
        "commands": [],
        "sources": {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for directory in [
                ROOT / f"quests/{number:03}",
                ROOT / f"solutions/{number:03}",
            ]
            for p in directory.rglob("*")
            if p.is_file()
        },
    }

    def execute(script, expected=0):
        result = runtime.exec(
            run, "set -euo pipefail\ncd ~/quest\n" + script, check=False, timeout=180
        )
        record["commands"].append(
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
        execute(
            'deadline=$((SECONDS+10))\nfor host in app1 app2 app3; do\n until ssh -n -o BatchMode=yes -o ConnectTimeout=1 -o ConnectionAttempts=1 -p 2222 root@"$host-${DQ_NAMESPACE#dq-}" true 2>/dev/null; do\n  [ "$SECONDS" -lt "$deadline" ] || exit 1\n  sleep 0.2\n done\ndone'
        )
        execute(catalog.script(number, 0, "setup"))
        runtime.capture_facts(
            dict(run, stage=0), catalog.quests[number].get("immutable", {}).get(0, [])
        )
        for objective in catalog.quests[number]["stages"][0]["objectives"]:
            if objective.get("keep"):
                execute(objective["check"])
        frozen = ROOT / "tests/fixtures/deepen-ansible-inputs"
        old = (frozen / f"{number:03}-legacy-check.sh").read_text()
        current = catalog.script(number, 0, "check")
        execute((frozen / f"{number:03}.sh").read_text(), 2 if number == 22 else 0)
        if number == 22:
            execute(
                "cat > message.j2 <<'LITERAL'\nstation={{ inventory_hostname }}\nroute=north\nLITERAL\nansible-playbook rollout.yml"
            )
            record["exact_old_reference"] = (
                "Stops at its first apply with undefined context"
            )
        execute(old)
        execute(current, 1)
        execute((ROOT / f"solutions/{number:03}/0.sh").read_text())
        execute(current)
        if number == 22:
            execute(
                "cat > message.j2 <<'ALTERNATIVE'\n# Host banner\nroute={{ station_routes[inventory_hostname].active }}\nstation={{ inventory_hostname }}\nformat=plain\nALTERNATIVE\nansible-playbook rollout.yml"
            )
            execute(current)
            record["alternative"] = "Reordered fields and unrelated metadata accepted"
        elif number == 55:
            execute(r"""python3 -I - <<'MERGE'
from pathlib import Path
import yaml
p=Path('ansible.cfg');p.write_text(p.read_text()+'\nhash_behaviour=merge\n')
for name,profile in [('group_vars/east.yml',{'zone':'east'}),('group_vars/west.yml',{'zone':'west'}),('host_vars/app2.yml',{'window':'standby'})]:Path(name).write_text(yaml.safe_dump({'service_profile':profile},sort_keys=False))
MERGE
ansible-playbook rollout.yml
""")
            execute(current)
            execute(r"""python3 -I - <<'EXPRESSIONS'
from pathlib import Path
import yaml
p=Path('ansible.cfg');p.write_text(p.read_text().replace('hash_behaviour=merge','hash_behaviour=replace'))
Path('group_vars/all.yml').write_text(yaml.safe_dump({'route_version':'north-ready','profile_defaults':{'route':'north-ready','zone':'unassigned','window':'primary'},'service_profile':"{{ profile_defaults | combine(site_profile) | combine(host_profile | default({})) }}"},sort_keys=False))
for name,values in [('group_vars/east.yml',{'site_profile':{'zone':'east'}}),('group_vars/west.yml',{'site_profile':{'zone':'west'}}),('host_vars/app2.yml',{'host_profile':{'window':'standby'}})]:Path(name).write_text(yaml.safe_dump(values,sort_keys=False))
EXPRESSIONS
ansible-playbook rollout.yml
""")
            execute(current)
            execute(
                "printf '%s\n' 'host_profile: {window: retired}' > host_vars/app2.yml"
            )
            execute(old)
            execute(current, 1)
            record["alternative"] = (
                "Current hash-merge configuration and evaluated combine expressions accepted"
            )
            record["desired_scope_drift"] = (
                "Rejected while published data and whole old check still pass"
            )
        else:
            execute(
                "printf '%s\n' 'allow_duplicates: false' > roles/base/meta/main.yml"
            )
            execute(old)
            execute(current, 1)
            execute(r"""python3 -I - <<'INCLUDE'
from pathlib import Path
import yaml
p=Path('roles/banner/tasks/main.yml');tasks=yaml.safe_load(p.read_text());tasks.insert(0,{'name':'Construct each caller prerequisite','ansible.builtin.include_role':{'name':'base','allow_duplicates':True}});p.write_text(yaml.safe_dump(tasks,sort_keys=False))
Path('roles/banner/meta/main.yml').write_text('dependencies: []\n')
INCLUDE
ansible-playbook rollout.yml
""")
            execute(current)
            record["alternative"] = (
                "Dynamic role composition accepted with metadata dependency absent"
            )
            record["dependency_dedup"] = (
                "Rejected while default fleet result and whole old check still pass"
            )
        record["result"] = "PASS"
    except BaseException as error:
        record["error"] = repr(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            record["teardown"] = "PASS"
        finally:
            (folder / f"{number:03}-shortcuts.json").write_text(
                json.dumps(record, indent=2) + "\n"
            )
