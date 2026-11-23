"""The production poll retains known diagnoses across the output boundary."""
from subprocess import CompletedProcess, TimeoutExpired

import pytest

from devops_quests.catalog import Catalog
from devops_quests.engine import Engine
from devops_quests.store import Store
from scripts.validate_i18n import diagnostic_errors


@pytest.mark.asyncio
@pytest.mark.parametrize(("level", "failed_objective"), [(18, 0), (43, 2), (76, 5)])
async def test_final_poll_retains_complete_probe_markers(tmp_path, level, failed_objective):
    store = Store(tmp_path / "progress.db")
    token = store.login("admin", store.bootstrap().read_text().strip(), "diagnostic-fixture")
    user = store.session(token)["user_id"]
    catalog = Catalog()
    objectives = catalog.quests[level]["stages"][0]["objectives"]
    calls = []

    class Runtime:
        def exec(self, run, script, **kwargs):
            index = len(calls)
            assert script == "set -euo pipefail\ncd ~/quest\n" + objectives[index]["check"]
            assert kwargs == {"check": False, "timeout": 25}
            calls.append(index)
            if index != failed_objective:
                return CompletedProcess([], 0, "", "")
            if level == 76:
                raise TimeoutExpired([], 25, output=b"[DQ:dag_contract]", stderr=b"synthetic timeout")
            stderr = ("x" * 1990) + " token=example-canary\n\x1b[31m[DQ:board_rollout]"
            if level == 18:
                stdout = "[DQ:content_1]\n[DQ:content_2]\n[DQ:content_3]"
                return CompletedProcess([], 1, stdout, "synthetic SSH stderr")
            return CompletedProcess([], 7, "", stderr)

    run = store.create_run(user, level, "free")
    result = await Engine(store, catalog, Runtime()).poll(run, final=True)
    assert calls == list(range(len(objectives)))
    assert result["status"] == "active"
    assert result["goals"][failed_objective] is False
    failure, = result["check_result"]["remaining"]
    assert failure["objective"] == failed_objective
    if level == 76:
        assert failure["code"] is None
        assert failure["diagnostic_keys"] == ["dag_contract"]
        assert failure["reason"] == "checks.cause.timeout"
    elif level == 18:
        assert failure["code"] == 1
        assert failure["diagnostic_keys"] == ["content_1", "content_2", "content_3"]
        assert "synthetic SSH stderr" in failure["detail"]
    else:
        assert failure["code"] == 7
        assert failure["diagnostic_keys"] == ["board_rollout"]
        assert len(failure["detail"]) == 2000
        assert "example-canary" not in failure["detail"]


def test_auditor_rejects_empty_causes_unknown_anchors_and_invalid_dependency_orders():
    link = "[Guide](guides#guide=kubernetes-10&section=primary)"
    valid = {
        "diagnostics.service": f"The selector may miss its Pod. {link}",
        "diagnostics.dns": f"The lookup may fail. {link}",
    }
    anchors = {"kubernetes-10": {"en": {"primary": 1}}}
    assert not list(diagnostic_errors(
        {"diagnostic_dependencies": {"dns": ["service"]}}, {"en": valid}, anchors,
    ))
    assert {error["error"] for error in diagnostic_errors({}, {"en": {}}, anchors)} == set()
    assert {error["error"] for error in diagnostic_errors(
        {"diagnostic_dependencies": {"dns": ["unknown"]}},
        {"en": {**valid, "diagnostics.dns": link}},
        {},
    )} == {"invalid_diagnostic_dependencies", "invalid_diagnostic_cause", "unknown_diagnostic_anchor"}
    assert list(diagnostic_errors(
        {"diagnostic_dependencies": {"dns": ["service"], "service": ["dns"]}},
        {"en": valid}, anchors,
    ))[0]["error"] == "invalid_diagnostic_dependencies"
