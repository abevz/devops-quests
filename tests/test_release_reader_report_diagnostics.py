"""New diagnostic wrappers retain command failures and successful observations."""

import os
from pathlib import Path
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def objective(number, index, stage=0):
    quest = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())
    return quest["stages"][stage]["objectives"][index]["check"]


def run_check(tmp_path, number, index, commands=None, *, stage=0):
    bin_path = tmp_path / "bin"
    bin_path.mkdir()
    for name, body in (commands or {}).items():
        command = bin_path / name
        command.write_text("#!/bin/bash\n" + body)
        command.chmod(0o755)
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", objective(number, index, stage=stage)],
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


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_034_replica_observation_preserves_pipeline_status(tmp_path, code):
    result = run_check(tmp_path, 34, 0, {
        "kubectl": f"exit {code}\n", "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == code
    assert ("[DQ:board_replicas]" in result.stderr) == (code != 0)


def test_034_failed_pod_selection_stops_before_http_exec(tmp_path):
    result = run_check(tmp_path, 34, 4, {"kubectl": """
if [ "$1" = get ]; then exit 7; fi
printf touched > exec-called
printf north
"""})
    assert result.returncode == 7
    assert "[DQ:board_http]" in result.stderr
    assert not (tmp_path / "exec-called").exists()


@pytest.mark.parametrize("text,good", [
    (None, False), ("old record\n", False), ("healthy fleet checked\n", True),
])
def test_035_observes_workstation_safety_record(tmp_path, text, good):
    if text is not None:
        (tmp_path / "safety-check.txt").write_text(text)
    result = run_check(tmp_path, 35, 0)
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:safety_record]" in result.stderr) == (not good)


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_053_live_plan_retains_detailed_exit_code(tmp_path, code):
    result = run_check(tmp_path, 53, 2, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:module_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("route,code", [("north", 0), ("south", 1), ("", 1)])
def test_054_observes_current_process_route(tmp_path, route, code):
    result = run_check(tmp_path, 54, 1, {"kubectl": f"printf '%s' '{route}'\n"})
    assert result.returncode == code
    assert ("[DQ:handover_route]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("index,marker", [(1, "handover_route"), (2, "handover_rollout")])
@pytest.mark.parametrize("code", [1, 7, 127])
def test_054_failed_observation_is_explained(tmp_path, index, marker, code):
    result = run_check(tmp_path, 54, index, {"kubectl": f"exit {code}\n"})
    # The route objective is a test of command substitution; its status is 1.
    assert result.returncode == (1 if index == 1 else code)
    assert f"[DQ:{marker}]" in result.stderr


def test_054_successful_rollout_has_no_failure_marker(tmp_path):
    result = run_check(tmp_path, 54, 2, {"kubectl": "exit 0\n"})
    assert result.returncode == 0
    assert "[DQ:" not in result.stdout + result.stderr


@pytest.mark.parametrize("contents,code", [(None, 1), ("0\n", 1), ("2\n", 0)])
def test_056_observes_applied_replica_file(tmp_path, contents, code):
    if contents is not None:
        (tmp_path / "replicas.txt").write_text(contents)
    result = run_check(tmp_path, 56, 1)
    assert result.returncode == code
    assert ("[DQ:capacity_file]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_056_live_plan_retains_detailed_exit_code(tmp_path, code):
    result = run_check(tmp_path, 56, 2, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:capacity_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [7, 127])
def test_059_failed_state_prefix_stops_before_identity_checks(tmp_path, code):
    result = run_check(tmp_path, 59, 0, {
        "tofu": f"printf 'local_file.ledger\\n'\nexit {code}\n",
    })
    assert result.returncode == code
    assert "[DQ:move_state]" in result.stderr
    assert "[DQ:move_identity]" not in result.stdout + result.stderr


def test_059_existing_identity_marker_is_not_duplicated(tmp_path):
    result = run_check(tmp_path, 59, 0, {
        "tofu": "if [ \"$1\" = state ]; then printf 'local_file.ledger\\n'; else printf '{}'; fi\n",
        "jq": "cat >/dev/null\nprintf file-id\n",
        "cat": """
case "$1" in
  original-id) printf file-id ;;
  /run/dq/facts/0/original-id) printf different-id ;;
  *) /bin/cat "$@" ;;
esac
""",
    })
    assert result.returncode == 1
    assert "[DQ:move_identity]" in result.stdout
    assert "[DQ:move_state]" not in result.stdout + result.stderr


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_059_plan_retains_detailed_exit_code(tmp_path, code):
    result = run_check(tmp_path, 59, 1, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:move_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("index,marker", [
    (0, "delivery_permissions"), (2, "delivery_source"), (3, "delivery_sync"),
])
def test_061_missing_environment_stops_before_api(tmp_path, index, marker):
    result = run_check(tmp_path, 61, index, {"kubectl": "touch api-called\n"})
    assert result.returncode == 1
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "api-called").exists()


def test_061_required_denials_are_successful_observations(tmp_path):
    (tmp_path / "platform.env").write_text("ARGO_NAMESPACE=argo\n")
    result = run_check(tmp_path, 61, 0, {"kubectl": """
if [ "$3" = patch ] && [ "$4" = secret/station-repository ]; then
  printf yes; exit 0
fi
printf no
exit 1
"""})
    assert result.returncode == 0
    assert "[DQ:" not in result.stdout + result.stderr


@pytest.mark.parametrize("index,marker", [(2, "delivery_source"), (3, "delivery_sync")])
def test_061_api_failure_is_not_hidden_by_successful_jq(tmp_path, index, marker):
    (tmp_path / "platform.env").write_text("GIT_URL=http://git/repository.git\n")
    (tmp_path / "release-commit").write_text("original-release\n")
    result = run_check(tmp_path, 61, index, {
        "kubectl": "printf '{}'\nexit 7\n", "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == 7
    assert f"[DQ:{marker}]" in result.stderr


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_061_rollout_retains_command_status(tmp_path, code):
    result = run_check(tmp_path, 61, 4, {"kubectl": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:delivery_rollout]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("response,code", [("north-61", 0), ("retired", 1), ("", 1)])
def test_061_observes_service_response(tmp_path, response, code):
    result = run_check(tmp_path, 61, 5, {"kubectl": f"printf '%s' '{response}'\n"})
    assert result.returncode == code
    assert ("[DQ:delivery_http]" in result.stderr) == (code != 0)
