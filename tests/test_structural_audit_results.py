"""Result checks must accept noncanonical source layout without losing their required properties."""

import json
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
        "renamed-module",
        "slash-name",
        "extra-resource",
        "data-only",
        "wrong-type",
        "wrong-name",
        "wrong-id",
        "missing-receipt",
    ],
)
@pytest.mark.parametrize("objective", [0, 1])
def test_026_tracks_the_existing_container_by_managed_identity(
    tmp_path, variant, objective
):
    quest = tmp_path / "quest"
    binary = tmp_path / "bin"
    quest.mkdir()
    binary.mkdir()
    receipt = "a" * 64
    if variant != "missing-receipt":
        (quest / "original-id").write_text(receipt + "\n")
    item = {
        "mode": "managed",
        "type": "docker_container",
        "address": "docker_container.worker",
        "values": {"name": "rail-worker", "id": receipt},
    }
    if variant == "slash-name":
        item["values"]["name"] = "/rail-worker"
    if variant == "data-only":
        item["mode"] = "data"
    if variant == "wrong-type":
        item["type"] = "docker_image"
    if variant == "wrong-name":
        item["values"]["name"] = "other"
    if variant == "wrong-id":
        item["values"]["id"] = "b" * 64
    root = {"resources": [item]}
    if variant == "renamed-module":
        item["address"] = "module.renamed.docker_container.existing"
        root = {"child_modules": [{"address": "module.renamed", "resources": [item]}]}
    if variant == "extra-resource":
        root["resources"].insert(
            0, {"mode": "managed", "type": "docker_image", "values": {"id": "other"}}
        )
    (quest / "state.json").write_text(json.dumps({"values": {"root_module": root}}))
    for name, body in [
        ("tofu", "print(pathlib.Path('state.json').read_text())"),
        ("docker", f"print('{receipt}')"),
    ]:
        p = binary / name
        p.write_text("#!" + sys.executable + "\nimport pathlib\n" + body + "\n")
        p.chmod(0o755)
    check = yaml.safe_load((ROOT / "quests/026/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][objective]["check"]
    result = subprocess.run(
        ["bash", "-c", check],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": str(binary) + ":" + os.environ["PATH"],
        },
        text=True,
        capture_output=True,
        timeout=5,
    )
    good = variant not in {"data-only", "wrong-type", "wrong-name"} and (
        objective == 0 or variant not in {"wrong-id", "missing-receipt"}
    )
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    assert "Traceback" not in result.stdout + result.stderr
    if not good:
        assert "[DQ:condition_" in result.stdout


@pytest.mark.parametrize("layout", ["reference", "renamed-handler", "extra-task"])
@pytest.mark.parametrize("wrong", [None, "content", "mode", "owner"])
def test_096_current_file_contract_does_not_require_one_restore_source_shape(
    tmp_path, layout, wrong
):
    quest = tmp_path / "quest"
    quest.mkdir()
    (quest / "rollout.yml").write_text(layout)
    binary = tmp_path / "bin"
    binary.mkdir()
    ssh = binary / "ssh"
    ssh.write_text(
        "#!"
        + sys.executable
        + '\nimport os,subprocess,sys\ncommand=sys.argv[-1]\nwrong=os.environ["WRONG"]\nif wrong and ((wrong=="content" and "cat " in command) or (wrong=="mode" and "%a" in command) or (wrong=="owner" and "%u:%g" in command)): raise SystemExit(1)\nraise SystemExit(0)\n'
    )
    ssh.chmod(0o755)
    check = yaml.safe_load((ROOT / "quests/096/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][2]["check"]
    result = subprocess.run(
        ["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + check],
        env={
            **os.environ,
            "HOME": str(tmp_path),
            "PATH": str(binary) + ":" + os.environ["PATH"],
            "DQ_NAMESPACE": "dq-fixture",
            "WRONG": wrong or "",
        },
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert (result.returncode == 0) is (wrong is None), result.stdout + result.stderr
    if wrong:
        assert "[DQ:" in result.stdout
