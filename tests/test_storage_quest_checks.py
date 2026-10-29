"""Regression checks for missing identities and failed data/API reads."""

import hashlib
import io
import tarfile
import json
import os
import subprocess

import pytest

from devops_quests.catalog import ROOT


def run_check(tmp_path, number, stage, kubectl, facts, *, tar=None, archive=None):
    home = tmp_path / 'home'
    (home / 'quest').mkdir(parents=True)
    if archive is not None:
        (home / 'quest/ledger.tar').write_bytes(archive)
    fact_dir = tmp_path / 'facts'
    fact_dir.mkdir()
    for name, value in facts.items():
        (fact_dir / name).write_text(value)
    bin_dir = tmp_path / 'bin'
    bin_dir.mkdir()
    for name, script in {'kubectl': kubectl, **({'tar': tar} if tar else {})}.items():
        path = bin_dir / name
        path.write_text('#!/bin/bash\n' + script)
        path.chmod(0o755)
    source = (ROOT / f'quests/{number}/check-{stage}.sh').read_text().replace('/run/dq/facts/0', str(fact_dir))
    environment = {**os.environ, 'HOME': str(home), 'PATH': f'{bin_dir}:{os.environ["PATH"]}', 'DQ_NAMESPACE': 'test'}
    return subprocess.run(['bash', '-c', source], capture_output=True, text=True, env=environment, timeout=10)


@pytest.mark.parametrize('pod, accepted', [('new-pod', True), ('', False)])
def test_statefulset_requires_a_real_replacement_pod(tmp_path, pod, accepted):
    kubectl = f'''case "$1 $2" in
      'get statefulset') echo '{{"metadata":{{"uid":"sts"}},"spec":{{"serviceName":"shelf","template":{{"spec":{{"containers":[{{"volumeMounts":[{{"name":"ledger","mountPath":"/data"}}]}}]}}}}}},"status":{{"readyReplicas":1}}}}' ;;
      'get pvc') echo '{{"metadata":{{"uid":"pvc"}}}}' ;;
      'get pod') if [ -n '{pod}' ]; then echo '{{"metadata":{{"uid":"{pod}"}}}}'; else exit 1; fi ;;
      'get service') echo '{{"spec":{{"clusterIP":"None","selector":{{"app":"shelf"}}}}}}' ;;
      'exec --pod-running-timeout=2s') if [[ "$*" == *wget* ]]; then echo ledger-111; fi ;;
      *) exit 1 ;;
    esac\n'''
    result = run_check(tmp_path, '111', 0, kubectl, {'original-statefulset-uid': 'sts', 'original-pvc-uid': 'pvc', 'original-pod-uid': 'old-pod'})
    assert (result.returncode == 0) is accepted, result.stdout + result.stderr
    if not accepted:
        assert 'pod UID matches required relationship' in result.stdout


def make_archive(names):
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode='w') as archive:
        for name in names:
            member = tarfile.TarInfo(name)
            archive.addfile(member, io.BytesIO(b''))
    return result.getvalue()


def test_failed_archive_read_cannot_match_empty_file_checksum(tmp_path):
    empty_hash = hashlib.sha256(b'').hexdigest()
    tar = 'if [ "$1" = tf ]; then echo ledger.txt; else exit 1; fi\n'
    kubectl = 'if [ "$1 $2" = "get pvc" ]; then echo claim; else exit 1; fi\n'
    result = run_check(tmp_path, '128', 0, kubectl, {'original-ledger.sha256': empty_hash, 'original-pvc-uid': 'claim'}, tar=tar, archive=make_archive(['ledger.txt']))
    assert result.returncode != 0
    assert 'ledger.tar ledger.txt checksum' in result.stdout


def test_cleanup_query_error_is_not_treated_as_absence(tmp_path):
    data = {'key': 'value'}
    digest = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
    contract = json.dumps({'control_uid': 'control-uid', 'control_hash': digest})
    control = json.dumps({'metadata': {'uid': 'control-uid'}, 'data': data})
    kubectl = f'''if [ "$1 $2 $3" = 'get configmap station' ]; then exit 1
    elif [ "$1 $2 $3" = 'get secret station-record' ]; then exit 0
    elif [ "$1 $2 $3" = 'get secret control' ]; then cat <<'JSON'
{control}
JSON
    else exit 1; fi\n'''
    result = run_check(tmp_path, '129', 0, kubectl, {'cleanup-contract.json': contract})
    assert result.returncode != 0
    assert 'query configmap/station: ✗' in result.stdout
    assert 'configmap/station absent: ✗' not in result.stdout
    assert 'value' not in result.stdout


def test_archive_rejects_extra_member_named_newline(tmp_path):
    empty_hash = hashlib.sha256(b'').hexdigest()
    kubectl = 'if [ "$1 $2" = "get pvc" ]; then echo claim; else exit 1; fi\n'
    result = run_check(tmp_path, '128', 0, kubectl, {'original-ledger.sha256': empty_hash, 'original-pvc-uid': 'claim'}, archive=make_archive(['ledger.txt', '\n']))
    assert result.returncode != 0
    assert 'ledger.tar contains exactly ledger.txt: ✗' in result.stdout


def test_storage_diagnostic_messages_cover_all_markers_and_languages():
    import re

    from devops_quests.catalog import Catalog

    catalog = Catalog()
    for number in (111, 124, 128, 129):
        quest = catalog.public(number)
        markers = set()
        for path in (ROOT / f"quests/{number}").glob("check-*.sh"):
            markers.update(re.findall(r"\[DQ:([a-z0-9_]+)\]", path.read_text()))
        if number == 111:
            markers.update(("uid_statefulset", "uid_pvc", "uid_pod"))
        assert markers
        for marker in markers:
            assert set(quest["diagnostics"][marker]) >= {"en", "pl", "es", "de", "ru"}


def test_every_failed_storage_condition_emits_a_localizable_marker(tmp_path):
    import re

    scenarios = [
        ("111", 0, "exit 1\n", {}, {"uid_statefulset", "uid_pvc", "uid_pod", "service_name", "ready", "mount", "clusterip", "selector", "http", "dns"}),
        ("124", 0, "exit 1\n", {}, {"volume", "pv_uid_fact", "pv_uid", "class", "reclaim", "phase", "claimref", "http", "original"}),
        ("124", 1, "exit 1\n", {}, {"volume", "pv_uid_fact", "pv_uid", "class", "reclaim", "phase", "claimref", "http", "replacement"}),
        ("128", 1, "exit 1\n", {}, {"entries", "archive_hash", "pvc_uid", "file_hash", "http_hash"}),
        ("129", 0, "exit 1\n", {}, {"config_query", "secret_query", "control_uid", "control_hash"}),
        ("129", 0, "if [ \"$2\" = configmap ]; then echo configmap/station; elif [ \"$3\" = station-record ]; then echo secret/station-record; else exit 1; fi\n", {}, {"config_absent", "secret_absent", "control_uid", "control_hash"}),
    ]
    for index, (number, stage, kubectl, facts, expected) in enumerate(scenarios):
        result = run_check(tmp_path / str(index), number, stage, kubectl, facts)
        assert result.returncode != 0
        markers = re.findall(r"\[DQ:([a-z0-9_]+)\]", result.stdout)
        assert len(markers) == len(result.stdout.splitlines()), result.stdout
        assert set(markers) == expected
