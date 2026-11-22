"""Renewal/digest annotations preserve upstream failures and content predicates."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("index,marker", [
    (1, "token_lease"), (2, "token_capabilities"), (3, "issuer_capabilities"),
])
def test_048_source_failure_stops_before_vault_access(tmp_path, index, marker):
    (tmp_path / "platform.env").write_text("false\nprintf unexpected > continued\n")
    result = run_check(tmp_path, 48, index, {"curl": "touch curl-called\n"})
    assert result.returncode == 1
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "continued").exists()
    assert not (tmp_path / "curl-called").exists()


@pytest.mark.parametrize("curl_status,jq_status", [(0, 0), (7, 0), (0, 4)])
def test_048_lease_pipeline_preserves_transport_and_json_failures(tmp_path, curl_status, jq_status):
    (tmp_path / "platform.env").write_text("export VAULT_ADDR=http://synthetic\n")
    (tmp_path / "station-token").write_text("synthetic-token")
    result = run_check(tmp_path, 48, 1, {
        "curl": f"printf response\nexit {curl_status}\n",
        "jq": f"cat >/dev/null\nexit {jq_status}\n",
    })
    assert result.returncode == (jq_status or curl_status)
    assert ("[DQ:token_lease]" in result.stderr) == bool(jq_status or curl_status)


@pytest.mark.parametrize("content,good", [("north-49", True), ("other", False)])
def test_049_http_preserves_the_observed_response(tmp_path, content, good):
    result = run_check(tmp_path, 49, 3, {"kubectl": f"printf '{content}\\n'\n"})
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:board_http]" in result.stderr) == (not good)


@pytest.mark.parametrize("status", [0, 1, 7, 127])
def test_049_rollout_preserves_detailed_status(tmp_path, status):
    result = run_check(tmp_path, 49, 2, {"kubectl": f"exit {status}\n"})
    assert result.returncode == status
    assert ("[DQ:board_rollout]" in result.stderr) == bool(status)
