"""New diagnostic wrappers retain command failures and successful observations."""

import os
from pathlib import Path
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def objective(number, index):
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    return quest["stages"][0]["objectives"][index]["check"]


def run_check(tmp_path, number, index, commands=None):
    bin_path = tmp_path / "bin"
    bin_path.mkdir()
    for name, body in (commands or {}).items():
        command = bin_path / name
        command.write_text("#!/bin/bash\n" + body)
        command.chmod(0o755)
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", objective(number, index)],
        cwd=tmp_path,
        env={**os.environ, "PATH": f"{bin_path}:{os.environ['PATH']}"},
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_030_plan_retains_detailed_exit_code(tmp_path, code):
    result = run_check(tmp_path, 30, 2, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:release_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_031_rollout_retains_failure_status(tmp_path, code):
    result = run_check(tmp_path, 31, 0, {"kubectl": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:reader_rollout]" in result.stderr) == (code != 0)


def test_031_failed_pod_selection_stops_before_exec(tmp_path):
    result = run_check(tmp_path, 31, 1, {"kubectl": """
if [ "$1" = get ]; then exit 7; fi
printf touched > exec-called
printf north
"""})
    assert result.returncode == 7
    assert "[DQ:reader_route]" in result.stderr
    assert not (tmp_path / "exec-called").exists()


@pytest.mark.parametrize("route,code", [("north", 0), ("south", 1)])
def test_031_observes_route_file(tmp_path, route, code):
    result = run_check(tmp_path, 31, 1, {"kubectl": f"""
if [ "$1" = get ]; then printf reader-pod; else printf {route}; fi
"""})
    assert result.returncode == code
    assert ("[DQ:reader_route]" in result.stderr) == (code != 0)


def test_031_failed_deployment_read_does_not_pass_through_pipeline(tmp_path):
    result = run_check(tmp_path, 31, 2, {
        "kubectl": "exit 7\n", "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == 7
    assert "[DQ:secret_reference]" in result.stderr


@pytest.mark.parametrize("text,mode,content_ok,mode_ok", [
    (None, None, False, False),
    ("app3\n", 0o600, False, False),
    ("app1\napp2\napp3\n", 0o644, True, True),
    ("app1\napp2\napp3\n", 0o600, True, False),
])
def test_032_observes_local_report(tmp_path, text, mode, content_ok, mode_ok):
    if text is not None:
        report = tmp_path / "fleet.txt"
        report.write_text(text)
        report.chmod(mode)
    for index, marker, good in (
        (0, "report_content", content_ok), (1, "report_mode", mode_ok),
    ):
        case_path = tmp_path / str(index)
        case_path.mkdir()
        if text is not None:
            (case_path / "fleet.txt").write_text(text)
            (case_path / "fleet.txt").chmod(mode)
        result = run_check(case_path, 32, index)
        assert result.returncode == (0 if good else 1)
        assert (f"[DQ:{marker}]" in result.stderr) == (not good)
