"""Exercise the shipped 046 observations through their actual shell entrypoints."""

import os
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def fixture_run(tmp_path, objective, variant):
    home = tmp_path / "home"
    quest = home / "quest"
    binary = tmp_path / "bin"
    quest.mkdir(parents=True)
    binary.mkdir()
    for n in (1, 2, 3):
        p = quest / f"app{n}"
        p.write_text("north-46\n")
        p.chmod(0o600)
    if variant == "wrong-banner":
        (quest / "app2").write_text("retired\n")
    (quest / "scenario").write_text(variant)
    (quest / "rollout.yml").write_text("supplied program\n")
    ssh = binary / "ssh"
    ssh.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import pathlib,subprocess,sys
host = sys.argv[-2].split('@')[1].split('-')[0]
quest = pathlib.Path.home() / 'quest'
scenario = (quest / 'scenario').read_text()
if scenario == 'missing' and host == 'app2': raise SystemExit(1)
if scenario == 'malformed': print('not JSON'); raise SystemExit(0)
command = sys.argv[-1].replace('/srv/site/banner.txt', str((quest / host).resolve()))
raise SystemExit(subprocess.run(['bash','-c',command]).returncode)
"""
    )
    late_writer = (
        "import pathlib,sys,time\n"
        "p=pathlib.Path(sys.argv[1])\n"
        "(p.parent/'writer-started').touch()\n"
        "release=p.parent/'release-writer'\n"
        "deadline=time.monotonic()+30\n"
        "while not release.exists() and time.monotonic()<deadline: time.sleep(.02)\n"
        "if release.exists():\n"
        " p.write_text('retired'+chr(10))\n"
        " p.chmod(0o644)\n"
        " (p.parent/'writer-finished').write_text('done')\n"
    )
    play = binary / "ansible-playbook"
    play.write_text(
        "#!"
        + sys.executable
        + "\n"
        + """import json,pathlib,subprocess,sys,time
assert sys.argv[1:] == ['--tags','inspect','rollout.yml']
variant = pathlib.Path('scenario').read_text()
p = pathlib.Path('app2')
if variant == 'late-writer':
 subprocess.Popen([sys.executable,'-c',DQ_LATE_WRITER,str(p.resolve())],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 time.sleep(30)
if variant in ('content','masked'): p.write_text('retired\n')
if variant == 'mode': p.chmod(0o644)
if variant == 'same-bytes-write': p.write_bytes(p.read_bytes())
stats = {'app'+str(n):{'changed':0,'failed':0,'unreachable':0} for n in (1,2,3)}
if variant in ('changed','failed','unreachable'): stats['app2'][variant] = 1
if variant == 'missing-recap': del stats['app3']
if variant == 'conflicting-alias': stats['app2']['dark'] = 1
if variant in ('json','conflicting-alias'): print(json.dumps({'stats':stats}))
else:
 print('PLAY RECAP ***')
 for host,row in stats.items(): print(host+' : '+' '.join(k+'='+str(v) for k,v in row.items()))
if variant == 'process': raise SystemExit(1)
""".replace("'retired\n'", "'retired\\n'").replace("DQ_LATE_WRITER", repr(late_writer))
    )
    for p in (ssh, play):
        p.chmod(0o755)
    code = yaml.safe_load((ROOT / "quests/046/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][objective]["check"]
    return subprocess.run(
        ["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + code],
        env={
            **os.environ,
            "HOME": str(home),
            "PATH": str(binary) + ":" + os.environ["PATH"],
            "DQ_NAMESPACE": "dq-fixture",
        },
        text=True,
        capture_output=True,
        timeout=15,
    )


@pytest.mark.parametrize(
    "variant,good",
    [
        ("reference", True),
        ("equivalent-command", True),
        ("content", False),
        ("mode", False),
        ("same-bytes-write", False),
        ("masked", False),
        ("missing", False),
        ("malformed", False),
        ("process", False),
    ],
)
def test_banner_observation_accepts_effect_not_module_shape(tmp_path, variant, good):
    result = fixture_run(tmp_path, 1, variant)
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    assert "Traceback" not in result.stdout + result.stderr
    # A rejected probe must preserve the learner's original banner data and mode.
    for host in (1, 2, 3):
        banner = tmp_path / "home" / "quest" / f"app{host}"
        assert banner.read_text() == "north-46\n"
        assert banner.stat().st_mode & 0o7777 == 0o600
    if not good:
        assert "[DQ:inspection_" in result.stdout


@pytest.mark.parametrize(
    "variant,good",
    [
        ("reference", True),
        ("json", True),
        ("changed", False),
        ("failed", False),
        ("unreachable", False),
        ("missing-recap", False),
        ("conflicting-alias", False),
        ("process", False),
    ],
)
def test_real_inspection_recap_is_independent_of_source_shape(tmp_path, variant, good):
    result = fixture_run(tmp_path, 2, variant)
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    assert "Traceback" not in result.stdout + result.stderr
    # A rejected probe must preserve the learner's original banner data and mode.
    for host in (1, 2, 3):
        banner = tmp_path / "home" / "quest" / f"app{host}"
        assert banner.read_text() == "north-46\n"
        assert banner.stat().st_mode & 0o7777 == 0o600
    if not good:
        assert "[DQ:inspection_" in result.stdout


def test_initial_write_selection_has_observable_different_content_and_mode():
    setup = (ROOT / "quests/046/setup-0.sh").read_text()
    assert setup.count("chmod 0600 /srv/site/banner.txt") == 3
    assert "content: 'retired" in setup
    assert "mode: '0644'" in setup
    assert "north-46" in setup


@pytest.mark.parametrize("variant", ["reference", "wrong-banner", "missing"])
def test_banner_constraint_has_named_failure_without_stderr_shadowing(
    tmp_path, variant
):
    result = fixture_run(tmp_path, 3, variant)
    assert (result.returncode == 0) is (variant == "reference"), (
        result.stdout + result.stderr
    )
    assert "Traceback" not in result.stdout + result.stderr
    if result.returncode:
        assert "[DQ:banner_2]" in result.stdout
        assert not result.stderr


@pytest.mark.parametrize("variant", ["reference", "symlink", "empty", "missing"])
def test_inspection_record_presence_has_a_named_failure(tmp_path, variant):
    home = tmp_path / "home"
    quest = home / "quest"
    quest.mkdir(parents=True)
    if variant in {"reference", "empty"}:
        (quest / "inspection.log").write_text(
            "record" if variant == "reference" else ""
        )
    elif variant == "symlink":
        (quest / "saved.log").write_text("record")
        (quest / "inspection.log").symlink_to("saved.log")
    check = yaml.safe_load((ROOT / "quests/046/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][0]["check"]
    result = subprocess.run(
        ["bash", "-c", "cd ~/quest\n" + check],
        env={**os.environ, "HOME": str(home)},
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert (result.returncode == 0) is (variant in {"reference", "symlink"})
    if result.returncode:
        assert "[DQ:inspection_log]" in result.stdout


@pytest.mark.parametrize("objective", [1, 2])
def test_timed_out_inspection_cannot_leave_a_late_banner_writer(tmp_path, objective):
    import time

    result = fixture_run(tmp_path, objective, "late-writer")
    quest = tmp_path / "home" / "quest"
    # Let a surviving worker act only after the checker has returned. A
    # controller-only timeout would allow it to overwrite the restored banner.
    assert (quest / "writer-started").exists()
    (quest / "release-writer").touch()
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline and not (quest / "writer-finished").exists():
        time.sleep(0.02)
    assert result.returncode != 0
    assert "[DQ:inspection_" in result.stdout
    assert "Traceback" not in result.stdout + result.stderr
    assert not (quest / "writer-finished").exists()
    for host in (1, 2, 3):
        banner = quest / f"app{host}"
        assert banner.read_text() == "north-46\n"
        assert banner.stat().st_mode & 0o7777 == 0o600
