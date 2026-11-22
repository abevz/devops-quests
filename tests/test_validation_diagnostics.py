"""Quest 039 annotations preserve detailed status and observation errors."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("status", [0, 1, 2, 127])
def test_039_retains_normal_plan_exit_status(tmp_path, status):
    result = run_check(tmp_path, 39, 3, {"tofu": f"exit {status}\n"})
    assert result.returncode == status
    assert ("[DQ:validation_plan]" in result.stderr) == (status != 0)


@pytest.mark.parametrize("text,good", [(None, False), ("wrong\n", False), ("3\n", True)])
def test_039_observes_timetable_file(tmp_path, text, good):
    if text is not None:
        (tmp_path / "timetable.txt").write_text(text)
    result = run_check(tmp_path, 39, 1)
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:timetable_content]" in result.stderr) == (not good)


@pytest.mark.parametrize("tofu_status,jq_status", [(0, 0), (7, 0), (0, 4)])
def test_039_retains_upstream_and_downstream_pipeline_failures(tmp_path, tofu_status, jq_status):
    result = run_check(tmp_path, 39, 2, {
        "tofu": f"printf 3\nexit {tofu_status}\n",
        "jq": f"cat >/dev/null\nexit {jq_status}\n",
    })
    status = jq_status or tofu_status
    assert result.returncode == status
    assert ("[DQ:departures_output]" in result.stderr) == (status != 0)
