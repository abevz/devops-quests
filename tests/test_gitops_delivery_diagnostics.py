"""Source failures retain errexit, environment scope and named diagnostics."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("quest,index", [(41, 0), (41, 1), (41, 3), (41, 4), (42, 1)])
def test_platform_input_failure_has_one_fallback(tmp_path, quest, index):
    result = run_check(tmp_path, quest, index)
    assert result.returncode == 1
    assert result.stdout.count("[DQ:platform_inputs]") == 1


def test_failing_sourced_input_stops_before_repository_access(tmp_path):
    (tmp_path / "platform.env").write_text("false\nprintf unexpected > continued\n")
    result = run_check(tmp_path, 41, 0, {"git": "touch git-called\n"})
    assert result.returncode == 1
    assert "[DQ:platform_inputs]" in result.stdout
    assert not (tmp_path / "continued").exists()
    assert not (tmp_path / "git-called").exists()


@pytest.mark.parametrize("status", [0, 7])
def test_git_keeps_sourced_environment_and_specific_failure(tmp_path, status):
    (tmp_path / "platform.env").write_text("export DQ_TEST_SOURCE_VALUE=present\n")
    result = run_check(tmp_path, 41, 0, {"git": f"""
test "$DQ_TEST_SOURCE_VALUE" = present || exit 9
touch git-called
exit {status}
"""})
    assert (tmp_path / "git-called").exists()
    assert result.returncode == (1 if status else 0)
    assert ("[DQ:fetch]" in result.stdout) == bool(status)
    assert "[DQ:platform_inputs]" not in result.stdout


@pytest.mark.parametrize("status", [0, 1, 7, 127])
def test_043_rollout_preserves_command_status(tmp_path, status):
    result = run_check(tmp_path, 43, 2, {"kubectl": f"exit {status}\n"})
    assert result.returncode == status
    assert ("[DQ:board_rollout]" in result.stderr) == bool(status)


def test_043_failed_git_observation_stops_before_status_read(tmp_path):
    (tmp_path / "platform.env").write_text("export GIT_URL=local DQ_NAMESPACE=bay\n")
    result = run_check(tmp_path, 43, 1, {
        "git": "exit 7\n", "kubectl": "touch api-called\n", "jq": "cat >/dev/null\n",
    })
    assert result.returncode == 7
    assert "[DQ:application_sync]" in result.stderr
    assert not (tmp_path / "api-called").exists()
