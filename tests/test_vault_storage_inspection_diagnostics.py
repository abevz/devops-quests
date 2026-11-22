"""Annotations retain input failure, credential cleanup and host-group boundaries."""

import pytest

from test_release_reader_report_diagnostics import run_check


@pytest.mark.parametrize("index", [1, 2])
def test_044_missing_environment_is_not_reported_as_a_policy_failure(tmp_path, index):
    result = run_check(tmp_path, 44, index)
    assert result.returncode == 1
    assert result.stdout.count("[DQ:vault_inputs]") == 1
    assert "[DQ:reader]" not in result.stdout
    assert "[DQ:cap_" not in result.stdout


@pytest.mark.parametrize("index", [1, 2])
def test_044_source_failure_retains_errexit(tmp_path, index):
    (tmp_path / "platform.env").write_text("exit 7\nprintf unexpected > continued\n")
    result = run_check(tmp_path, 44, index, {"curl": "touch curl-called\n"})
    assert result.returncode == 7
    assert "[DQ:vault_inputs]" in result.stdout
    assert not (tmp_path / "continued").exists()
    assert not (tmp_path / "curl-called").exists()


@pytest.mark.parametrize("success", [False, True])
def test_044_existing_failure_and_success_clean_header_files(tmp_path, monkeypatch, success):
    temporary = tmp_path / "temporary"
    temporary.mkdir()
    monkeypatch.setenv("TMPDIR", str(temporary))
    (tmp_path / "platform.env").write_text(
        "export VAULT_MANAGER_TOKEN=synthetic-manager VAULT_READER_TOKEN=synthetic-reader "
        "VAULT_ADDR=http://local\n"
    )
    result = run_check(tmp_path, 44, 1, {
        "curl": "printf response\n",
        "jq": "cat >/dev/null\nprintf " + ("north-secret" if success else "other") + "\n",
    })
    assert result.returncode == (0 if success else 1)
    assert ("[DQ:reader]" in result.stdout) == (not success)
    assert "[DQ:vault_inputs]" not in result.stdout
    assert not list(temporary.iterdir())


@pytest.mark.parametrize("upstream,downstream", [(0, 0), (7, 0), (0, 4)])
def test_045_uid_pipeline_retains_both_command_failures(tmp_path, upstream, downstream):
    (tmp_path / "original-pvc-uid").write_text("original")
    result = run_check(tmp_path, 45, 0, {
        "kubectl": f"printf response\nexit {upstream}\n",
        "jq": f"cat >/dev/null\nexit {downstream}\n",
    })
    assert result.returncode == (downstream or upstream)
    assert ("[DQ:claim_identity]" in result.stderr) == bool(downstream or upstream)


def test_046_missing_namespace_names_each_guarded_host(tmp_path, monkeypatch):
    monkeypatch.delenv("DQ_NAMESPACE", raising=False)
    result = run_check(tmp_path, 46, 3, {"ssh": "touch ssh-called\n"})
    assert result.returncode == 1
    for number in (1, 2, 3):
        assert result.stdout.count(f"[DQ:banner_{number}]") == 1
    assert "[DQ:probe_0_3]" not in result.stdout
    assert not (tmp_path / "ssh-called").exists()
