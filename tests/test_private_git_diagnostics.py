"""Private Git annotations retain stage boundaries and short-circuit failures."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("stage,index,marker", [
    (0, 0, "git_state"), (0, 2, "git_ancestry"),
    (1, 0, "argo_release"), (1, 1, "remote_ancestry"),
])
def test_050_source_failure_stops_before_git(tmp_path, stage, index, marker):
    (tmp_path / "platform.env").write_text("false\nprintf unexpected > continued\n")
    result = run_check(tmp_path, 50, index, {"git": "touch git-called\n"}, stage=stage)
    assert result.returncode == 1
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "continued").exists()
    assert not (tmp_path / "git-called").exists()


def test_050_failed_remote_observation_does_not_read_argo_state(tmp_path):
    (tmp_path / "platform.env").write_text("export GIT_URL=http://synthetic DQ_NAMESPACE=bay\n")
    result = run_check(tmp_path, 50, 0, {
        "git": "exit 7\n", "kubectl": "touch api-called\n",
    }, stage=1)
    assert result.returncode == 7
    assert "[DQ:argo_release]" in result.stderr
    assert not (tmp_path / "api-called").exists()


@pytest.mark.parametrize("rollout,annotation", [(0, 0), (7, 0), (0, 4)])
def test_050_rollout_and_tracking_keep_their_separate_failure_status(tmp_path, rollout, annotation):
    result = run_check(tmp_path, 50, 2, {
        "kubectl": f"""
if [ "$1" = rollout ]; then exit {rollout}; fi
touch annotation-read
printf '{{}}'
""",
        "jq": f"cat >/dev/null\nexit {annotation}\n",
    }, stage=1)
    assert result.returncode == (rollout or annotation)
    assert ("[DQ:controller_tracking]" in result.stderr) == bool(rollout or annotation)
    assert (tmp_path / "annotation-read").exists() == (rollout == 0)
