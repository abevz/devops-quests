"""Failure annotations retain detailed-plan and negative-RBAC semantics."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("code", [0, 1, 2, 127])
def test_036_retains_detailed_plan_status(tmp_path, code):
    result = run_check(tmp_path, 36, 4, {"tofu": f"exit {code}\n"})
    assert result.returncode == code
    assert ("[DQ:ledger_plan]" in result.stderr) == (code != 0)


@pytest.mark.parametrize("text,good", [(None, False), ("wrong\n", False), ("revision-36\n", True)])
def test_036_checks_existing_ledger_content(tmp_path, text, good):
    if text is not None:
        (tmp_path / "ledger.txt").write_text(text)
    result = run_check(tmp_path, 36, 1)
    assert result.returncode == (0 if good else 1)
    assert ("[DQ:ledger_content]" in result.stderr) == (not good)


@pytest.mark.parametrize("present", [False, True])
def test_036_retains_absence_check(tmp_path, present):
    if present:
        (tmp_path / "retired-ledger.txt").write_text("revision-36\n")
    result = run_check(tmp_path, 36, 2)
    assert result.returncode == int(present)
    assert ("[DQ:retired_absent]" in result.stderr) == present


def test_037_role_read_retains_pipeline_failure(tmp_path):
    result = run_check(tmp_path, 37, 0, {
        "kubectl": "exit 7\n", "jq": "cat >/dev/null\nexit 0\n",
    })
    assert result.returncode == 7
    assert "[DQ:role_contract]" in result.stderr


@pytest.mark.parametrize("index,marker", [(2, "restricted_denied"), (3, "secrets_denied")])
@pytest.mark.parametrize("request_status", [0, 1, 7])
def test_037_retains_unsuccessful_request_semantics(tmp_path, index, marker, request_status):
    result = run_check(tmp_path, 37, index, {"kubectl": f"""
case "$1" in
    get) printf identity-pod ;;
    exec) printf synthetic-fixture-only ;;
    --token=*) exit {request_status} ;;
    *) exit 99 ;;
esac
"""})
    # The shipped negative check accepts any unsuccessful final request.
    assert result.returncode == (1 if request_status == 0 else 0)
    assert (f"[DQ:{marker}]" in result.stderr) == (request_status == 0)


@pytest.mark.parametrize("index,marker", [(1, "route_read"), (2, "restricted_denied"), (3, "secrets_denied")])
def test_037_failed_pod_lookup_stops_before_credential_read(tmp_path, index, marker):
    result = run_check(tmp_path, 37, index, {"kubectl": """
if [ "$1" = get ]; then exit 7; fi
printf touched > credential-read
exit 0
"""})
    assert result.returncode == 7
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "credential-read").exists()


@pytest.mark.parametrize("index,marker", [(2, "restricted_denied"), (3, "secrets_denied")])
def test_037_failed_credential_read_stops_before_denial_request(tmp_path, index, marker):
    result = run_check(tmp_path, 37, index, {"kubectl": """
if [ "$1" = get ]; then printf identity-pod; exit 0; fi
if [ "$1" = exec ]; then exit 9; fi
printf touched > denial-request
exit 1
"""})
    assert result.returncode == 9
    assert f"[DQ:{marker}]" in result.stderr
    assert not (tmp_path / "denial-request").exists()
