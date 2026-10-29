"""A fleet check must compare the whole file, not trust line-delimited fields."""

import os
import subprocess

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize(
    ("number", "stage", "expected"),
    [(2, 0, "north-ready"), (10, 0, "release-10"), (20, 1, "release-20"), (63, 0, "stable-63")],
)
def test_multiline_banner_cannot_forge_content_or_mode(tmp_path, number, stage, expected):
    quest = tmp_path / "quest"
    quest.mkdir()
    message = tmp_path / "message"
    message.write_text(expected + "\n644\nchecked\n")
    message.chmod(0o600)
    marker = tmp_path / "marker"
    marker.write_text("wrong\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    commands = {
        "ssh": r'''#!/bin/bash
script=${@: -1}
script=${script//\/srv\/site\/recovery-checked/$TEST_MARKER}
script=${script//\/srv\/site\/message/$TEST_MESSAGE}
exec bash -c "$script"
''',
        "curl": '#!/bin/sh\nprintf "%s\\n" "$TEST_EXPECTED"\n',
        "ansible-playbook": '#!/bin/sh\nfor n in 1 2 3; do echo "app$n : changed=0 failed=0"; done\n',
    }
    for name, contents in commands.items():
        path = binary / name
        path.write_text(contents)
        path.chmod(0o755)
    result = subprocess.run(
        ["bash", str(ROOT / f"quests/{number:03}/check-{stage}.sh")],
        env={**os.environ, "HOME": str(tmp_path), "DQ_NAMESPACE": "dq-test", "PATH": str(binary) + ":" + os.environ["PATH"], "TEST_MESSAGE": str(message), "TEST_MARKER": str(marker), "TEST_EXPECTED": expected},
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode != 0
    for n in (1, 2, 3):
        assert f"app{n}-test /srv/site/message = {expected}: ✗" in result.stdout
        assert f"app{n}-test /srv/site/message mode = 644: ✗" in result.stdout


def test_rescue_requires_a_block_to_handle_failure(tmp_path):
    (tmp_path / "rollout.yml").write_text(
        "- hosts: fleet\n  serial: 1\n  tasks:\n"
        "  - rescue:\n"
        "    - ansible.builtin.copy: {src: previous.txt, dest: /srv/site/message, mode: '0644'}\n"
        "      notify: Reload banner\n"
        "    always:\n    - ansible.builtin.debug: {msg: done}\n"
    )
    source = (ROOT / "quests/063/check-0.sh").read_text()
    program = source.split("<<'SCOPE'\n", 1)[1].split("\nSCOPE\n", 1)[0]
    result = subprocess.run(["python3", "-"], input=program, cwd=tmp_path, capture_output=True, text=True, timeout=5)
    assert result.returncode != 0
    assert "first task block is a nonempty list" in result.stdout


def test_rescue_serial_must_be_numeric_one(tmp_path):
    (tmp_path / "rollout.yml").write_text(
        "- hosts: fleet\n  serial: true\n  tasks:\n"
        "  - block:\n    - ansible.builtin.debug: {msg: work}\n"
        "    rescue:\n"
        "    - ansible.builtin.copy: {src: previous.txt, dest: /srv/site/message, mode: '0644'}\n"
        "      notify: Reload banner\n"
        "    always:\n    - ansible.builtin.debug: {msg: done}\n"
    )
    source = (ROOT / "quests/063/check-0.sh").read_text()
    program = source.split("<<'SCOPE'\n", 1)[1].split("\nSCOPE\n", 1)[0]
    result = subprocess.run(["python3", "-"], input=program, cwd=tmp_path, capture_output=True, text=True, timeout=5)
    assert result.returncode != 0
    assert "first play serial = 1" in result.stdout
