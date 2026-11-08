"""Observe 028 batch progression without parsing a prescribed playbook layout."""

import os
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(
    "variant",
    [
        "reference",
        "role-command",
        "wrong-order",
        "parallel",
        "wrong-content",
        "missing",
        "malformed",
        "process",
    ],
)
def test_delivery_progression_uses_observed_batch_effects_and_restores_files(
    tmp_path, variant
):
    quest = tmp_path / "quest"
    quest.mkdir()
    binary = tmp_path / "bin"
    binary.mkdir()
    for host in ("app1", "app2", "app3"):
        p = quest / host
        p.write_text("original\n")
        p.chmod(0o600)
    (quest / "scenario").write_text(variant)
    ssh = binary / "ssh"
    ssh.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import pathlib,shlex,subprocess,sys
host=sys.argv[-2].split('@')[1].split('-')[0]
command=shlex.split(sys.argv[-1]);position=command.index('-c')+1
command[position]=command[position].replace('/srv/site/message',str(pathlib.Path(host).resolve()))
raise SystemExit(subprocess.run(command).returncode)
"""
    )
    ssh.chmod(0o755)
    play = binary / "ansible-playbook"
    play.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import base64,json,os,pathlib,sys
assert sys.argv[1:]==['rollout.yml']
variant=pathlib.Path('scenario').read_text();hosts=['app1','app2','app3']
order=['app2','app1','app3'] if variant=='wrong-order' else hosts
records=[]
for host in order:
 pathlib.Path(host).write_text('wrong' if variant=='wrong-content' else 'north-ready\\n')
 records.append({'batch':hosts if variant=='parallel' else [host],'values':{h:base64.b64encode(pathlib.Path(h).read_bytes()).decode() for h in hosts}})
output=pathlib.Path(os.environ['DQ_BATCH_OBSERVATION'])
if variant!='missing':output.write_text('not JSON' if variant=='malformed' else '\\n'.join(json.dumps(x) for x in records))
if variant=='process':raise SystemExit(1)
"""
    )
    play.chmod(0o755)
    check = yaml.safe_load((ROOT / "quests/028/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][2]["check"]
    result = subprocess.run(
        ["bash", "-c", check],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": str(binary) + ":" + os.environ["PATH"],
            "DQ_NAMESPACE": "dq-fixture",
        },
        capture_output=True,
        text=True,
        timeout=25,
    )
    assert (result.returncode == 0) is (variant in {"reference", "role-command"}), (
        result.stdout + result.stderr
    )
    assert "Traceback" not in result.stdout + result.stderr
    if result.returncode:
        assert "[DQ:" in result.stdout
    for host in ("app1", "app2", "app3"):
        assert (quest / host).read_text() == "original\n"
        assert (quest / host).stat().st_mode & 0o7777 == 0o600
