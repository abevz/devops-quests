"""Release and admission checks reject missing or split evidence."""

import json
import os
import re
import subprocess

from devops_quests.catalog import ROOT, Catalog


def run_quest_check(tmp_path, number, stage, kubectl, facts=None):
    home = tmp_path / "home"
    (home / "quest").mkdir(parents=True)
    fact_dir = tmp_path / "facts"
    fact_dir.mkdir()
    for name, value in (facts or {}).items():
        (fact_dir / name).write_text(value)
    binaries = tmp_path / "bin"
    binaries.mkdir()
    program = binaries / "kubectl"
    program.write_text("#!/bin/bash\n" + kubectl)
    program.chmod(0o755)
    source = (ROOT / f"quests/{number}/check-{stage}.sh").read_text().replace("/run/dq/facts/0", str(fact_dir)).replace("/tmp/rendered-overlay.yaml", str(tmp_path / "rendered.yaml"))
    environment = {**os.environ, "HOME": str(home), "PATH": f'{binaries}:{os.environ["PATH"]}', "DQ_NAMESPACE": "test"}
    return subprocess.run(["bash", "-c", source], env=environment, text=True, capture_output=True, timeout=15)


def assert_localized_markers(number, result):
    markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
    assert markers and len(markers) == len(result.stdout.splitlines())
    assert len(result.stdout) <= 2000
    messages = Catalog().public(number)["diagnostics"]
    for marker in markers:
        assert set(messages[marker]) >= {"en", "pl", "es", "de", "ru"}
    return set(markers)


def test_missing_canary_deployments_and_pod_ips_fail(tmp_path):
    kubectl = '''case "$1 $2" in
      'get deployment') echo '{"items":[]}' ;;
      'get service') echo '{"spec":{"selector":{"release":"board"}}}' ;;
      'get endpointslices') echo '{"items":[]}' ;;
      'get pods') exit 0 ;;
      'exec --pod-running-timeout=2s') printf blue-115 ;;
      *) exit 1 ;;
    esac\n'''
    result = run_quest_check(tmp_path, "115", 1, kubectl)
    assert result.returncode != 0
    markers = assert_localized_markers(115, result)
    assert {"blue_replicas", "blue_ready", "green_replicas", "green_ready", "endpoints", "ips_blue", "ips_green"} <= markers


def test_resources_and_readiness_must_be_on_same_admitted_pod(tmp_path):
    pods = {"items": [
        {"metadata": {}, "spec": {"containers": [{"resources": {"requests": {"cpu": "100m", "memory": "16Mi"}}}]}, "status": {}},
        {"metadata": {}, "spec": {"containers": [{"resources": {"limits": {"cpu": "200m", "memory": "32Mi"}}}]}, "status": {}},
        {"metadata": {}, "spec": {"containers": [{}]}, "status": {"containerStatuses": [{"ready": True}]}},
    ]}
    kubectl = f'''case "$1 $2" in
      'get pods') cat <<'JSON'
{json.dumps(pods)}
JSON
      ;;
      *) exit 1 ;;
    esac\n'''
    result = run_quest_check(tmp_path, "126", 0, kubectl)
    assert result.returncode != 0
    markers = assert_localized_markers(126, result)
    assert "same_pod" in markers
    assert not {"pod_requests", "pod_limits", "pod_ready"} & markers


def test_missing_overlay_and_monitoring_queries_explain_failures(tmp_path):
    for number in ("108", "127"):
        result = run_quest_check(tmp_path / number, number, 0, "exit 1\n", {"original-deployment-uid": "uid", "prometheus-target.json": '{"url":"http://private.invalid"}'})
        assert result.returncode != 0
        markers = assert_localized_markers(int(number), result)
        expected = {"render", "uid"} if number == "108" else {"up_status", "sum_status", "count_status", "target_health"}
        assert expected <= markers


def test_canary_does_not_count_missing_endpoint_names(tmp_path):
    deployments = {"items": [
        {"metadata": {"name": "blue"}, "spec": {"replicas": 3}, "status": {"readyReplicas": 3}},
        {"metadata": {"name": "green"}, "spec": {"replicas": 1}, "status": {"readyReplicas": 1}},
    ]}
    endpoints = {"items": [{"endpoints": [
        {"conditions": {"ready": True}, "targetRef": {"name": name}} for name in ("blue-a", "blue-b", "green-a", None)
    ]}]}
    kubectl = f'''case "$1 $2" in
      'get deployment') echo '{json.dumps(deployments)}' ;;
      'get service') echo '{{"spec":{{"selector":{{"release":"board"}}}}}}' ;;
      'get endpointslices') echo '{json.dumps(endpoints)}' ;;
      'get pods') if [[ "$*" == *app=blue* ]]; then printf 10.0.0.1; else printf 10.0.0.2; fi ;;
      'exec --pod-running-timeout=2s') if [[ "$*" == *10.0.0.2* ]]; then printf green-115; else printf blue-115; fi ;;
      *) exit 1 ;;
    esac\n'''
    result = run_quest_check(tmp_path, "115", 1, kubectl)
    assert result.returncode != 0
    assert "[DQ:endpoints]" in result.stdout


def test_each_failing_canary_pod_gets_a_diagnostic(tmp_path):
    kubectl = '''case "$1 $2" in
      'get pods') if [[ "$*" == *app=blue* ]]; then printf '10.0.0.1 10.0.0.2 10.0.0.3'; else printf 10.0.0.4; fi ;;
      'exec --pod-running-timeout=2s') printf incorrect ;;
      *) exit 1 ;;
    esac\n'''
    result = run_quest_check(tmp_path, "115", 1, kubectl)
    assert result.returncode != 0
    assert result.stdout.count("[DQ:pod_blue]") == 3
    assert result.stdout.count("[DQ:pod_green]") == 1
