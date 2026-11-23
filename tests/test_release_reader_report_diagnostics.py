"""New diagnostic wrappers retain command failures and successful observations."""

import os
from pathlib import Path
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def prepare_091_bay(tmp_path, *, platform=True):
    """Use the supplied relative workstation layout without changing HOME."""
    (tmp_path / "repository").mkdir()
    (tmp_path / "release-commit").write_text("a" * 40 + "\n")
    if platform:
        (tmp_path / "platform.env").write_text("export GIT_URL=http://source.invalid/repository\n")


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_091_release_head_wrapper_retains_fetch_status(tmp_path, code):
    prepare_091_bay(tmp_path)
    result = run_check(tmp_path, 91, 0, {"git": f"""
test "$1" = -C && test "$2" = repository || exit 98
if [ "$3" = fetch ]; then
  test "$4" = origin && test "$5" = main || exit 99
  printf 'fetch\\n' >> git-calls
  exit {code}
fi
test "$3" = rev-parse && test "$4" = origin/main || exit 99
printf 'rev-parse\\n' >> git-calls
printf '%s\\n' '{'a' * 40}'
"""})
    assert result.returncode == code
    assert ("[DQ:provenance_head]" in result.stderr) == (code != 0)
    assert (tmp_path / "git-calls").read_text().splitlines() == (
        ["fetch"] if code else ["fetch", "rev-parse"]
    )


@pytest.mark.parametrize("index,marker", [(1, "provenance_source"), (2, "provenance_sync")])
@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_091_api_wrapper_retains_pipeline_failure(tmp_path, index, marker, code):
    prepare_091_bay(tmp_path)
    # These two drivers control pipeline statuses, not application JSON semantics;
    # the native quest matrix exercises the actual jq predicates and Argo objects.
    result = run_check(tmp_path, 91, index, {
        "kubectl": f"printf '{{}}\\n'\nprintf 'raw API detail\\n' >&2\nexit {code}\n",
        "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == code
    assert "raw API detail" in result.stderr
    assert (f"[DQ:{marker}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_091_rollout_wrapper_retains_status_and_stderr(tmp_path, code):
    prepare_091_bay(tmp_path)
    result = run_check(tmp_path, 91, 3, {
        "kubectl": f"printf 'raw rollout detail\\n' >&2\nexit {code}\n",
    })
    assert result.returncode == code
    assert "raw rollout detail" in result.stderr
    assert ("[DQ:provenance_rollout]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("text,command_code,expected", [
    ("north-91", 0, 0), ("retired", 0, 1), ("", 7, 1),
])
def test_091_http_wrapper_retains_the_original_value_comparison(tmp_path, text, command_code, expected):
    prepare_091_bay(tmp_path)
    result = run_check(tmp_path, 91, 4, {
        "kubectl": f"printf '%s' '{text}'\nexit {command_code}\n",
    })
    assert result.returncode == expected
    assert ("[DQ:provenance_http]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("index,marker", [
    (0, "provenance_head"), (1, "provenance_source"), (2, "provenance_sync"),
])
def test_091_missing_supplied_input_is_named_before_external_commands(tmp_path, index, marker):
    prepare_091_bay(tmp_path, platform=False)
    result = run_check(tmp_path, 91, index, {
        name: "touch command-invoked\nexit 0\n" for name in ("git", "kubectl", "jq")
    })
    assert result.returncode == 1
    assert "platform.env" in result.stderr
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "command-invoked").exists()


def run_080_platform_check(tmp_path, stage, index, platform=None, commands=None, *, number=80):
    """Map the actual workstation directory; keep HOME and the check body intact."""
    import shlex

    bay = tmp_path / "quest"
    bay.mkdir()
    if platform is not None:
        (bay / "platform.env").write_text(platform)
    binary = tmp_path / "bin"
    binary.mkdir()
    for name, body in (commands or {}).items():
        program = binary / name
        program.write_text("#!/bin/bash\n" + body)
        program.chmod(0o755)
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    check = objective(number, index, stage=stage)
    assert check.count("cd ~/quest\n") == (1 if number == 80 or stage == 0 else 0)
    check = check.replace("cd ~/quest\n", "cd " + shlex.quote(str(bay)) + "\n")
    result = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", check],
        cwd=bay,
        env={**os.environ, "PATH": f"{binary}:{os.environ['PATH']}",
             "TMPDIR": str(scratch), "DQ_NAMESPACE": "dq-0123456789abcdef01234567"},
        capture_output=True, text=True, timeout=10,
    )
    assert list(scratch.iterdir()) == []
    return result


@pytest.mark.parametrize("stage,index", [(0, 0), (1, 0), (1, 1), (1, 4), (1, 6), (1, 7)])
def test_080_missing_provided_platform_input_is_named(tmp_path, stage, index):
    result = run_080_platform_check(tmp_path, stage, index)
    assert result.returncode == 1
    assert "platform.env" in result.stdout + result.stderr
    assert f"[DQ:probe_{stage}_{index}]" in result.stdout + result.stderr


@pytest.mark.parametrize("stage,index,known", [
    (0, 0, "repo"), (1, 0, "health"), (1, 1, "fetch"),
    (1, 4, "rollout"), (1, 6, "registry"), (1, 7, "http"),
])
@pytest.mark.parametrize("kind", ["known", "foreign", "opaque"])
def test_080_fallback_preserves_status_streams_and_known_detail(tmp_path, stage, index, known, kind):
    text = {"known": f"[DQ:{known}]", "foreign": "[DQ:unrelated_probe]", "opaque": "opaque failure"}[kind]
    result = run_080_platform_check(
        tmp_path, stage, index,
        f"printf '%s\\n' '{text}'\nprintf '%s\\n' 'raw stderr retained' >&2\nexit 23\n",
    )
    assert result.returncode == 23
    assert text in result.stdout
    assert "raw stderr retained" in result.stdout + result.stderr
    assert (f"[DQ:probe_{stage}_{index}]" in result.stdout + result.stderr) == (kind != "known")


@pytest.mark.parametrize("failure", ["none", "registry", "credential"])
def test_080_private_config_and_capture_are_cleaned_on_every_exit(tmp_path, failure):
    platform = "REGISTRY=registry.example\nREGISTRY_USER=reader\n"
    if failure != "credential":
        platform += "REGISTRY_PASSWORD=controlled-test-input\n"
    result = run_080_platform_check(tmp_path, 1, 6, platform, {
        "jq": "printf '%s\\n' 'registry.example/parcel@sha256:abcdef'\n",
        "curl": """
while [ "$#" -gt 0 ]; do
  if [ "$1" = --config ]; then
    shift
    test -s "$1" && test "$(stat -c %a "$1")" = 600 || exit 92
    printf '%s\\n' "$1" > config-observed
  fi
  shift
done
"""
        + ("exit 7\n" if failure == "registry" else "exit 0\n"),
    })
    text = result.stdout + result.stderr
    assert result.returncode == (0 if failure == "none" else 1)
    assert ("[DQ:registry]" in text) == (failure == "registry")
    assert ("[DQ:probe_1_6]" in text) == (failure == "credential")
    assert "controlled-test-input" not in text
    observed = tmp_path / "quest/config-observed"
    assert observed.exists() == (failure != "credential")
    if observed.exists():
        assert not Path(observed.read_text().strip()).exists()


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


@pytest.mark.parametrize("count,code", [(0, 1), (1, 0), (2, 1)])
def test_062_observes_exactly_one_policy(tmp_path, count, code):
    result = run_check(tmp_path, 62, 1, {
        "kubectl": "printf '{}'\n",
        "jq": f"cat >/dev/null\nprintf {count}\n",
    })
    assert result.returncode == code
    assert ("[DQ:isolation_policy_count]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("response,code", [("north-62", 0), ("retired", 1), ("", 1)])
def test_062_observes_permitted_caller_response(tmp_path, response, code):
    result = run_check(tmp_path, 62, 2, {"kubectl": f"printf '%s' '{response}'\n"})
    assert result.returncode == code
    assert ("[DQ:isolation_allowed]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("request_status,code", [(0, 1), (1, 0), (7, 0), (127, 0)])
def test_062_negative_probe_retains_existing_success_semantics(tmp_path, request_status, code):
    result = run_check(tmp_path, 62, 3, {"kubectl": f"exit {request_status}\n"})
    # The original condition rejects a successful unwanted request. A failed
    # command already counts as no success; this wrapper adds no new predicate.
    assert result.returncode == code
    assert ("[DQ:isolation_denied]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("index,station", [(3, "depot"), (4, "junction")])
@pytest.mark.parametrize("value,code", [(None, 1), ("retired", 1), ("north", 0)])
def test_064_observes_each_station_file(tmp_path, index, station, value, code):
    if value is not None:
        (tmp_path / f"{station}.txt").write_text(f"{value}:{station}\n")
    result = run_check(tmp_path, 64, index)
    assert result.returncode == code
    assert (f"[DQ:fanout_{station}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_064_live_plan_retains_detailed_exit_code(tmp_path, code):
    result = run_check(tmp_path, 64, 6, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:fanout_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 2, 3, 127])
def test_066_retention_plan_preserves_jq_status(tmp_path, code):
    result = run_check(tmp_path, 66, 0, {"jq": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:retention_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("helm_code,jq_code,code", [(0, 0, 0), (7, 0, 7), (0, 3, 3)])
def test_067_history_preserves_both_pipeline_statuses(tmp_path, helm_code, jq_code, code):
    result = run_check(tmp_path, 67, 1, {
        "helm": f"printf '[]'\nexit {helm_code}\n",
        "jq": f"cat >/dev/null\nexit {jq_code}\n",
    })
    assert result.returncode == code
    assert ("[DQ:helm_history]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_067_rollout_preserves_command_status(tmp_path, code):
    result = run_check(tmp_path, 67, 4, {"kubectl": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:helm_rollout]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("response,code", [("north-67", 0), ("retired", 1), ("", 1)])
def test_067_observes_local_worker_response(tmp_path, response, code):
    result = run_check(tmp_path, 67, 5, {"kubectl": f"printf '%s' '{response}'\n"})
    assert result.returncode == code
    assert ("[DQ:helm_http]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("number,stage,index,marker", [
    (68, 0, 0, "git_source"), (68, 0, 1, "git_health"),
    (68, 0, 4, "git_descendant"), (70, 0, 0, "secret_git_path"),
    (70, 1, 0, "secret_git_health"), (70, 1, 1, "secret_rollout"),
    (70, 1, 3, "secret_value"), (70, 1, 4, "secret_capabilities"),
    (70, 1, 5, "secret_http"),
])
def test_068_070_missing_environment_stops_before_external_commands(
    tmp_path, number, stage, index, marker,
):
    result = run_check(tmp_path, number, index, {
        "kubectl": "touch external-called\n", "git": "touch external-called\n",
        "curl": "touch external-called\n",
    }, stage=stage)
    assert result.returncode == 1
    assert result.stderr.count(f"[DQ:{marker}]") == 1
    assert not (tmp_path / "external-called").exists()


@pytest.mark.parametrize("number,stage,index,marker", [
    (68, 0, 2, "git_rollout"), (70, 1, 1, "secret_rollout"),
])
@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_068_070_rollout_retains_exit_status(tmp_path, number, stage, index, marker, code):
    (tmp_path / "platform.env").touch()
    result = run_check(tmp_path, number, index, {"kubectl": f"exit {code}\n"}, stage=stage)
    assert result.returncode == code
    assert (f"[DQ:{marker}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("number,stage,index,marker", [
    (68, 0, 0, "git_source"), (68, 0, 1, "git_health"),
    (70, 0, 0, "secret_git_path"), (70, 1, 0, "secret_git_health"),
])
@pytest.mark.parametrize("api_code,json_code,expected", [(7, 0, 7), (0, 4, 4), (0, 0, 0)])
def test_068_070_application_pipeline_retains_both_failures(
    tmp_path, number, stage, index, marker, api_code, json_code, expected,
):
    (tmp_path / "platform.env").write_text("GIT_URL=provided\n")
    (tmp_path / "release-commit").write_text("abc\n")
    result = run_check(tmp_path, number, index, {
        "kubectl": f"exit {api_code}\n", "jq": f"cat >/dev/null\nexit {json_code}\n",
    }, stage=stage)
    assert result.returncode == expected
    assert (f"[DQ:{marker}]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("number,stage,marker", [(68, 0, "git_http"), (70, 1, "secret_http")])
@pytest.mark.parametrize("correct", [True, False])
def test_068_070_observes_service_body(tmp_path, number, stage, marker, correct):
    (tmp_path / "platform.env").touch()
    index = 3 if number == 68 else 5
    response = f"north-{number}" if correct else "other"
    result = run_check(tmp_path, number, index, {"kubectl": f"printf %s {response}\n"}, stage=stage)
    assert result.returncode == (0 if correct else 1)
    assert (f"[DQ:{marker}]" in result.stderr) == (not correct)


@pytest.mark.parametrize("transport,json_status,expected", [(7, 0, 7), (0, 1, 1), (0, 0, 0)])
def test_070_capabilities_pipeline_retains_transport_and_denial_semantics(
    tmp_path, transport, json_status, expected,
):
    (tmp_path / "platform.env").write_text("VAULT_READER_TOKEN=provided\nVAULT_ADDR=http://provided\n")
    result = run_check(tmp_path, 70, 4, {
        "curl": f"exit {transport}\n", "jq": f"cat >/dev/null\nexit {json_status}\n",
    }, stage=1)
    assert result.returncode == expected
    assert ("[DQ:secret_capabilities]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("transport,json_status,expected", [(7, 0, 7), (0, 1, 1), (0, 0, 0)])
def test_073_capabilities_retains_pipeline_status(tmp_path, transport, json_status, expected):
    (tmp_path / "platform.env").write_text("VAULT_READER_TOKEN=provided\nVAULT_ADDR=http://provided\n")
    result = run_check(tmp_path, 73, 1, {
        "curl": f"exit {transport}\n", "jq": f"cat >/dev/null\nexit {json_status}\n",
    })
    assert result.returncode == expected
    assert ("[DQ:vault_capabilities]" in result.stderr) == (expected != 0)


def test_073_missing_environment_stops_before_policy_observation(tmp_path):
    result = run_check(tmp_path, 73, 1, {"curl": "touch api-called\n"})
    assert result.returncode == 1
    assert result.stderr.count("[DQ:vault_capabilities]") == 1
    assert not (tmp_path / "api-called").exists()


@pytest.mark.parametrize("index,marker", [
    (0, "webhook_hook"), (1, "webhook_revision"), (2, "webhook_source"),
    (3, "webhook_health"), (6, "webhook_acceptance"),
])
def test_075_missing_environment_stops_before_external_observation(tmp_path, index, marker):
    result = run_check(tmp_path, 75, index, {
        "curl": "touch api-called\n", "kubectl": "touch api-called\n",
        "git": "touch api-called\n", "jq": "touch api-called\n",
    })
    assert result.returncode == 1
    assert result.stderr.count(f"[DQ:{marker}]") == 1
    assert not (tmp_path / "api-called").exists()


def test_075_missing_webhook_environment_stops_before_hook_api(tmp_path):
    (tmp_path / "platform.env").touch()
    result = run_check(tmp_path, 75, 0, {"curl": "touch api-called\n"})
    assert result.returncode == 1
    assert "[DQ:webhook_hook]" in result.stderr
    assert not (tmp_path / "api-called").exists()


@pytest.mark.parametrize("api_status,json_status,expected", [(7, 0, 7), (0, 1, 1), (0, 0, 0)])
def test_075_hook_pipeline_retains_both_command_statuses(
    tmp_path, api_status, json_status, expected,
):
    (tmp_path / "platform.env").write_text(
        "GIT_URL=http://provided/rail/station.git\nGIT_USER=provided\nGIT_PASSWORD=provided\n"
    )
    (tmp_path / "webhook.env").touch()
    result = run_check(tmp_path, 75, 0, {
        "cat": "printf 7\n", "curl": f"exit {api_status}\n",
        "jq": f"/bin/cat >/dev/null\nexit {json_status}\n",
    })
    assert result.returncode == expected
    assert ("[DQ:webhook_hook]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_075_rollout_retains_command_status(tmp_path, code):
    result = run_check(tmp_path, 75, 4, {"kubectl": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:webhook_rollout]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("index,marker", [(0, "dag_validate"), (6, "dag_plan")])
@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_076_tofu_validation_and_plan_retain_exit_status(tmp_path, index, marker, code):
    result = run_check(tmp_path, 76, index, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert (f"[DQ:{marker}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_076_module_checksum_retains_exit_status(tmp_path, code):
    result = run_check(tmp_path, 76, 1, {"sha256sum": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:dag_module_source]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("north,good", [("dispatch:north", True), ("other", False), (None, False)])
def test_076_observes_applied_north_file(tmp_path, north, good):
    if north is not None:
        (tmp_path / "north.txt").write_text(north + "\n")
    result = run_check(tmp_path, 76, 3)
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:dag_north]" in result.stderr) == (not good)


@pytest.mark.parametrize("south,others,expected_marker", [
    ("wrong", False, "dag_south"), (None, True, "dag_south"),
    ("dispatch:north:south", False, "dag_delivery"),
    ("dispatch:north:south", True, None),
])
def test_076_south_failure_keeps_existing_branch_diagnostic_separate(
    tmp_path, south, others, expected_marker,
):
    if south is not None:
        (tmp_path / "south.txt").write_text(south + "\n")
    (tmp_path / "east.txt").write_text("dispatch:east\n" if others else "wrong\n")
    (tmp_path / "archive.txt").write_text(
        "dispatch:north:south|dispatch:east:archive\n" if others else "wrong\n"
    )
    result = run_check(tmp_path, 76, 4)
    output = result.stdout + result.stderr
    assert result.returncode == (1 if expected_marker else 0)
    assert output.count("[DQ:") == (1 if expected_marker else 0)
    if expected_marker:
        assert f"[DQ:{expected_marker}]" in output
    if south is None:
        assert "south.txt" in result.stderr  # Preserve the original read error too.


@pytest.mark.parametrize("index,marker", [(1, "pdb_replicas"), (2, "pdb_status")])
@pytest.mark.parametrize("api_status,json_status,expected", [(7, 0, 7), (0, 4, 4), (0, 0, 0)])
def test_077_pdb_pipeline_preserves_api_and_json_failures(
    tmp_path, index, marker, api_status, json_status, expected,
):
    result = run_check(tmp_path, 77, index, {
        "kubectl": f"exit {api_status}\n", "jq": f"cat >/dev/null\nexit {json_status}\n",
    })
    assert result.returncode == expected
    assert (f"[DQ:{marker}]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("index,marker", [(4, "eviction_request"), (5, "eviction_replacement"), (6, "eviction_observed")])
@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_077_eviction_predicate_retains_result(tmp_path, monkeypatch, index, marker, code):
    monkeypatch.setenv("DQ_NAMESPACE", "dq-0123456789abcdef01234567")
    result = run_check(tmp_path, 77, index, {
        "jq": f"/bin/cat >/dev/null\nexit {code}\n", "kubectl": "exit 0\n",
    })
    assert result.returncode == code
    assert (f"[DQ:{marker}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("body,cli_status,good", [("no", 1, True), ("yes", 0, False), ("", 7, False)])
def test_077_expected_authorization_denial_is_successful_observation(tmp_path, body, cli_status, good):
    result = run_check(tmp_path, 77, 7, {"kubectl": f"printf %s '{body}'\nexit {cli_status}\n"})
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:pod_status_denied]" in result.stderr) == (not good)


@pytest.mark.parametrize("number,index,stage,expected,marker", [
    (77, 3, 0, "north-77", "pdb_http"), (78, 3, 1, "north-78", "registry_http"),
])
@pytest.mark.parametrize("correct", [True, False])
def test_077_078_observes_actual_http_body(tmp_path, number, index, stage, expected, marker, correct):
    response = expected if correct else "other"
    result = run_check(tmp_path, number, index, {"kubectl": f"printf %s {response}\n"}, stage=stage)
    assert result.returncode == (0 if correct else 1)
    assert (f"[DQ:{marker}]" in result.stderr) == (not correct)


@pytest.mark.parametrize("stage,index,marker", [(0, 0, "registry_start"), (1, 1, "registry_pull_policy")])
def test_078_missing_environment_stops_before_api(tmp_path, stage, index, marker):
    result = run_check(tmp_path, 78, index, {
        "curl": "touch api-called\n", "kubectl": "touch api-called\n", "jq": "touch api-called\n",
    }, stage=stage)
    assert result.returncode == 1
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "api-called").exists()


@pytest.mark.parametrize("api_status,json_status,expected", [(7, 0, 7), (0, 4, 4), (0, 0, 0)])
def test_078_failed_image_policy_stops_before_pod_observation(tmp_path, api_status, json_status, expected):
    (tmp_path / "platform.env").touch()
    result = run_check(tmp_path, 78, 1, {
        "jq": f'''if [ "$1" = -er ]; then printf 'image@sha256:fixture'; exit 0; fi
/bin/cat >/dev/null
exit {json_status}
''',
        "kubectl": f'''if [ "$2" = pods ]; then touch pods-called; fi
exit {api_status}
''',
    }, stage=1)
    assert result.returncode == expected
    assert ("[DQ:registry_pull_policy]" in result.stderr) == (expected != 0)
    assert (tmp_path / "pods-called").exists() == (expected == 0)


@pytest.mark.parametrize("index,fields", [
    (2, ["dir_mode"]), (3, ["banner_mode", "route_mode"]),
    (4, ["banner_content"]), (5, ["route_content"]),
])
@pytest.mark.parametrize("mode", ["empty", "detailed", "opaque", "foreign"])
def test_079_failed_remote_probe_always_has_a_known_diagnostic(
    tmp_path, monkeypatch, index, fields, mode,
):
    monkeypatch.setenv("DQ_NAMESPACE", "dq-0123456789abcdef01234567")
    ssh = r"""remote="${@: -1}"
case MODE in
 detailed) printf '%s' "$remote" | grep -oE '\[DQ:host_[123]_[a-z_]+\]' | head -1 ;;
 opaque) printf '%s\n' 'opaque remote startup output' ;;
 foreign) printf '%s\n' '[DQ:unrelated_remote_message]' ;;
esac
exit 7
""".replace("MODE", mode)
    result = run_check(tmp_path, 79, index, {"ssh": ssh})
    expected = (
        [f"host_{host}_{field}" for host in (1, 2, 3) for field in fields]
        if mode == "detailed" else [f"ssh_{host}" for host in (1, 2, 3) for _ in fields]
    )
    import re
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout + result.stderr)
    assert result.returncode == 1
    assert [marker for marker in markers if marker != "unrelated_remote_message"] == expected
    if mode == "opaque":
        assert result.stdout.count("opaque remote startup output") == 3 * len(fields)
    if mode == "foreign":
        assert markers.count("unrelated_remote_message") == 3 * len(fields)


@pytest.mark.parametrize("stage,index", [(0, 0), (1, 0), (1, 2)])
def test_093_missing_supplied_platform_input_is_named(tmp_path, stage, index):
    result = run_080_platform_check(tmp_path, stage, index, number=93)
    assert result.returncode == 1
    assert "platform.env" in result.stdout + result.stderr
    assert f"[DQ:probe_{stage}_{index}]" in result.stdout


@pytest.mark.parametrize("stage,index,known", [(0, 0, "init"), (1, 0, "sealed"), (1, 2, "manager")])
@pytest.mark.parametrize("kind", ["known", "foreign", "opaque"])
def test_093_fallback_retains_status_and_existing_output(tmp_path, stage, index, known, kind):
    text = {"known": f"[DQ:{known}]", "foreign": "[DQ:unrelated_probe]", "opaque": "opaque failure"}[kind]
    result = run_080_platform_check(
        tmp_path, stage, index,
        f"printf '%s\\n' '{text}'\nprintf '%s\\n' 'raw stderr retained' >&2\nexit 23\n",
        number=93,
    )
    assert result.returncode == 23
    assert text in result.stdout
    assert "raw stderr retained" in result.stdout + result.stderr
    assert (f"[DQ:probe_{stage}_{index}]" in result.stdout) == (kind != "known")


@pytest.mark.parametrize("code", ["403", "500"])
def test_093_manager_header_and_capture_cleanup(tmp_path, code):
    result = run_080_platform_check(
        tmp_path, 1, 2,
        "VAULT_ADDR=http://provided.invalid\nVAULT_READER_TOKEN=controlled-reader\n"
        "VAULT_MANAGER_TOKEN=controlled-manager\n",
        {"curl": '''
while [ "$#" -gt 0 ]; do
 if [ "$1" = -H ]; then
  shift
  header=${1#@}
  test -f "$header" && test "$(stat -c %a "$header")" = 600 || exit 92
  printf '%s\\n' "$header" > header-observed
 fi
 shift
done
printf %s ''' + code + "\n"},
        number=93,
    )
    output = result.stdout + result.stderr
    assert result.returncode == (0 if code == "403" else 1)
    assert ("[DQ:manager]" in output) == (code != "403")
    assert "[DQ:probe_1_2]" not in output
    assert "controlled-reader" not in output and "controlled-manager" not in output
    header = tmp_path / "quest/header-observed"
    assert header.exists()
    assert not Path(header.read_text().strip()).exists()


@pytest.mark.parametrize("index,marker", [(1, "performance_replicas"), (4, "performance_ready")])
@pytest.mark.parametrize("api_status,json_status,expected", [(7, 0, 7), (0, 4, 4), (0, 0, 0)])
def test_094_replica_wrappers_retain_original_pipeline_status(
    tmp_path, index, marker, api_status, json_status, expected,
):
    result = run_check(tmp_path, 94, index, {
        "kubectl": f"printf '%s\\n' 'raw API stderr' >&2\nexit {api_status}\n",
        "jq": f"cat >/dev/null\nexit {json_status}\n",
    })
    assert result.returncode == expected
    assert "raw API stderr" in result.stderr
    assert (f"[DQ:{marker}]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("text,command_code,expected", [("north-94", 0, 0), ("other", 0, 1), ("", 7, 1)])
def test_094_http_wrapper_retains_value_comparison(tmp_path, text, command_code, expected):
    result = run_check(tmp_path, 94, 6, {
        "kubectl": f"printf %s '{text}'\nprintf '%s\\n' 'raw HTTP stderr' >&2\nexit {command_code}\n",
    })
    assert result.returncode == expected
    assert "raw HTTP stderr" in result.stderr
    assert ("[DQ:performance_http]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("baseline,expected", [("10", 0), ("9", 1), ("unreadable", 2)])
def test_094_baseline_wrapper_retains_original_numeric_test(tmp_path, baseline, expected):
    original = objective(94, 0)
    frozen = tmp_path / "initial-throttled"
    frozen.write_text(baseline)
    # Only map the readonly frozen-fact path; HOME and the predicate remain intact.
    check = original.replace("/run/dq/facts/0/initial-throttled", str(frozen))
    result = subprocess.run(["bash", "-euo", "pipefail", "-c", check], capture_output=True, text=True)
    assert result.returncode == expected
    assert ("[DQ:performance_baseline]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("fetch_status,ancestor_status,expected,calls", [
    (0, 0, 0, ["fetch", "rev-parse", "merge-base"]),
    (7, 0, 7, ["fetch"]),
    (0, 1, 1, ["fetch", "rev-parse", "merge-base"]),
    (0, 127, 127, ["fetch", "rev-parse", "merge-base"]),
])
def test_095_head_wrapper_preserves_fetch_and_ancestry(
    tmp_path, fetch_status, ancestor_status, expected, calls,
):
    import shlex

    prepare_091_bay(tmp_path)
    faulty = tmp_path / "faulty-commit"
    faulty.write_text("b" * 40 + "\n")
    binary = tmp_path / "bin"
    binary.mkdir()
    git = binary / "git"
    git.write_text(f'''#!/bin/bash
test "$1" = -C && test "$2" = repository || exit 98
printf '%s\\n' "$3" >> git-calls
case "$3" in
 fetch) exit {fetch_status} ;;
 rev-parse) printf '%s\\n' '{'a' * 40}' ;;
 merge-base) test "$4" = --is-ancestor && test "$5" = '{'b' * 40}' && test "$6" = origin/main || exit 99
             exit {ancestor_status} ;;
 *) exit 99 ;;
esac
''')
    git.chmod(0o755)
    check = objective(95, 0).replace("/run/dq/facts/0/faulty-commit", shlex.quote(str(faulty)))
    result = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", check], cwd=tmp_path,
        env={**os.environ, "PATH": f"{binary}:{os.environ['PATH']}"}, capture_output=True, text=True,
    )
    assert result.returncode == expected
    assert ("[DQ:rollback_head]" in result.stderr) == (expected != 0)
    assert (tmp_path / "git-calls").read_text().splitlines() == calls


@pytest.mark.parametrize("index,marker", [(1, "rollback_source"), (2, "rollback_sync"), (3, "rollback_rollout")])
@pytest.mark.parametrize("code", [0, 1, 7, 127])
def test_095_api_and_rollout_wrappers_preserve_status_and_detail(tmp_path, index, marker, code):
    prepare_091_bay(tmp_path)
    # Controlled command statuses exercise the wrapper, not the real jq predicate;
    # native validation covers the actual Application JSON and workload rollout.
    result = run_check(tmp_path, 95, index, {
        "kubectl": f"printf '{{}}\\n'\nprintf 'raw API detail\\n' >&2\nexit {code}\n",
        "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == code
    assert "raw API detail" in result.stderr
    assert (f"[DQ:{marker}]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("text,command_code,expected", [("north-95", 0, 0), ("retired", 0, 1), ("", 7, 1)])
def test_095_http_wrapper_retains_actual_value_comparison(tmp_path, text, command_code, expected):
    result = run_check(tmp_path, 95, 4, {
        "kubectl": f"printf %s '{text}'\nprintf 'raw HTTP error\\n' >&2\nexit {command_code}\n",
    })
    assert result.returncode == expected
    assert "raw HTTP error" in result.stderr
    assert ("[DQ:rollback_http]" in result.stderr) == (expected != 0)


@pytest.mark.parametrize("index,marker", [(0, "rollback_head"), (1, "rollback_source"), (2, "rollback_sync")])
def test_095_missing_platform_input_stops_before_commands(tmp_path, index, marker):
    prepare_091_bay(tmp_path, platform=False)
    result = run_check(tmp_path, 95, index, {
        name: "touch command-called\nexit 0\n" for name in ("git", "kubectl", "jq")
    })
    assert result.returncode == 1
    assert "platform.env" in result.stderr and f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "command-called").exists()


@pytest.mark.parametrize("kind,expected", [("match", 0), ("changed", 1), ("missing_archive", 1), ("missing_receipt", 1)])
def test_097_archive_wrapper_retains_original_hash_comparison(tmp_path, kind, expected):
    import hashlib
    import shlex

    archive = tmp_path / "recovery-image.tar"
    if kind != "missing_archive":
        archive.write_bytes(b"changed" if kind == "changed" else b"controlled archive bytes")
    receipt = tmp_path / "archive.sha256"
    if kind != "missing_receipt":
        receipt.write_text(hashlib.sha256(b"controlled archive bytes").hexdigest() + "\n")
    check = objective(97, 0).replace("/run/dq/facts/0/archive.sha256", shlex.quote(str(receipt)))
    result = subprocess.run(
        ["bash", "-euo", "pipefail", "-c", check], cwd=tmp_path, capture_output=True, text=True,
    )
    assert result.returncode == expected
    assert ("[DQ:recovery_archive]" in result.stderr) == (expected != 0)
    if kind in ("missing_archive", "missing_receipt"):
        assert "No such file" in result.stderr
