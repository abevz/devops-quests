"""087: a stale checkpoint cannot replace newer work or a live lock owner."""

import contextlib
import copy
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import threading
import urllib.error
import urllib.request
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.locking_backend import Backend, handler
from devops_quests.runtime import Runtime
from test_opentofu_rigid_checks import objective, python_source


@contextlib.contextmanager
def backend_service():
    backend = Backend()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler(backend))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield backend, 'http://127.0.0.1:' + str(server.server_port)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def request(url, method, value=None):
    data = json.dumps(value).encode() if value is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def test_native_http_lock_identity_rejects_stale_writes_and_unlocks():
    with backend_service() as (backend, url):
        a = {'ID': 'client-a', 'Who': 'alice', 'Operation': 'apply'}
        b = {'ID': 'client-b', 'Who': 'bob', 'Operation': 'console'}
        assert request(url + '/deployment', 'LOCK', a)[0] == 200
        assert request(url + '/deployment', 'LOCK', b)[0] == 423
        assert request(url + '/deployment', 'UNLOCK', {'ID': a['ID']})[0] == 200
        assert request(url + '/deployment', 'LOCK', b)[0] == 200
        assert request(url + '/deployment?ID=client-a', 'POST', {'serial': 3})[0] == 423
        assert request(url + '/deployment', 'UNLOCK', a)[0] == 409
        assert backend.lock == b and backend.state is None
        assert request(url + '/deployment?ID=client-b', 'POST', {'serial': 4})[0] == 200
        assert json.loads(backend.state)['serial'] == 4
        assert request(url + '/deployment', 'UNLOCK', b)[0] == 200
        assert request(url + '/deployment', 'DELETE')[0] == 405


@pytest.mark.parametrize('value,status', [
    ({'handle': 'unknown'}, 409),
    ({'handle': 'original', 'command': 'kill 1'}, 400),
    ({'handle': 'original', 'pid': 1}, 400),
    ({'handle': 42}, 400),
    ({'handle': 'x' * 17000}, 400),
    ({'handle': 'original'}, 202),
])
def test_completion_contract_is_bounded_to_registered_child(value, status):
    with backend_service() as (backend, url):
        backend.owner = {'registered': True, 'handle': 'original', 'running': True}
        assert request(url + '/owner/finish', 'POST', value)[0] == status
        assert backend.finish.is_set() == (status == 202)


@pytest.mark.parametrize('variant', [
    'reference', 'renamed', 'replaced-container', 'lost-progress', 'data-only',
    'stopped-container', 'unhealthy-container', 'wrong-lineage', 'rolled-back',
    'altered-checkpoint', 'missing-backup', 'older-backup', 'owner-running',
    'owner-force-unlocked', 'plan-changes',
])
def test_actual_recovery_predicate(monkeypatch, tmp_path, variant):
    monkeypatch.chdir(tmp_path)
    def record(kind, identity):
        return {'type': kind, 'mode': 'managed', 'name': 'arbitrary', 'instances': [{'attributes': {'id': identity}}]}
    backup = {'lineage': 'lineage-original', 'serial': 2, 'resources': [record('terraform_data', 'progress-original')]}
    current = copy.deepcopy(backup)
    current['serial'] = 3
    current['resources'].append(record('docker_container', 'physical-original'))
    physical = {'Id': 'physical-original', 'State': {'Running': True, 'Health': {'Status': 'healthy'}}}
    owner = {'completed': True, 'running': False}
    facts = {'container_id': 'physical-original', 'progress_id': 'progress-original', 'lineage': 'lineage-original', 'serial': 2, 'checkpoint_sha256': hashlib.sha256(b'original checkpoint').hexdigest(), 'backup_sha256': hashlib.sha256(json.dumps(backup, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
    (tmp_path / 'errored.tfstate').write_bytes(b'original checkpoint')
    if variant == 'replaced-container':
        current['resources'][-1]['instances'][0]['attributes']['id'] = 'replacement'
    elif variant == 'lost-progress':
        current['resources'].pop(0)
    elif variant == 'data-only':
        current['resources'][-1]['mode'] = 'data'
    elif variant == 'stopped-container':
        physical['State']['Running'] = False
    elif variant == 'unhealthy-container':
        physical['State']['Health']['Status'] = 'unhealthy'
    elif variant == 'wrong-lineage':
        current['lineage'] = 'replacement'
    elif variant == 'rolled-back':
        current['serial'] = 1
    elif variant == 'altered-checkpoint':
        (tmp_path / 'errored.tfstate').write_bytes(b'original checkpoint\n')
    elif variant == 'older-backup':
        backup['resources'] = []
    elif variant == 'owner-running':
        owner['running'] = True
    elif variant == 'owner-force-unlocked':
        owner['completed'] = False
    if variant != 'missing-backup':
        (tmp_path / 'before-recovery.tfstate').write_text(json.dumps(backup))
    original_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == '/run/dq/locking-identities.json':
            return json.dumps(facts)
        return original_read(path, *args, **kwargs)

    def cli(argv, **kwargs):
        if argv[:3] == ['tofu', 'state', 'pull']:
            return SimpleNamespace(stdout=json.dumps(current), returncode=0)
        if argv[:2] == ['docker', 'inspect']:
            return SimpleNamespace(stdout=json.dumps([physical]), returncode=0)
        assert argv[:2] == ['tofu', 'plan']
        return SimpleNamespace(returncode=2 if variant == 'plan-changes' else 0)

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            pass

        def read(self):
            return json.dumps(owner)

    monkeypatch.setattr(Path, 'read_text', read)
    monkeypatch.setattr(subprocess, 'run', cli)
    monkeypatch.setattr(urllib.request, 'urlopen', lambda *_a, **_kw: Response())
    code = python_source(objective('087', 2))
    with pytest.raises(SystemExit) as result:
        exec(compile(code, '087-shipped-recovery', 'exec'), {'__name__': '__main__'})
    assert result.value.code == (0 if variant in ('reference', 'renamed') else 1)


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
@pytest.mark.parametrize('unsafe_owner', [False, True], ids=['newer-work', 'live-owner'])
def test_native_recovery_rejects_lost_work_and_wrong_unlock(unsafe_owner):
    runtime = Runtime(ROOT / '.state/runtime')
    run = {'id': secrets.token_hex(12), 'level': 87}
    catalog = Catalog()
    folder = Path(os.environ.get('DQ_DEEPEN_EVIDENCE', ROOT / 'artifacts/locking-shortcuts'))
    folder.mkdir(parents=True, exist_ok=True)
    log = {'quest': 87, 'unsafe_owner': unsafe_owner}

    def execute(script, expected=None):
        value = runtime.exec(run, 'set -euo pipefail\ncd ~/quest\n' + script, check=False, timeout=180)
        log.setdefault('commands', []).append({'script': script, 'exit': value.returncode, 'stdout': value.stdout, 'stderr': value.stderr})
        if expected is not None:
            assert value.returncode == expected, value.stdout + value.stderr
        return value

    try:
        runtime.create(run)
        check = catalog.script(87, 0, 'check')
        execute(catalog.script(87, 0, 'setup'), 0)
        execute(check, 1)
        if unsafe_owner:
            # A stale error's owner is not today's lock; force-unlocking today's
            # live native owner lets later work converge but cannot prove its EOF.
            execute('handle=$(curl -fsS http://127.0.0.1:18787/owner | jq -r .handle)\ntofu force-unlock -force "$handle"', 0)
            script = (ROOT / 'solutions/087/0.sh').read_text()
            script = script.replace("curl -fsS http://127.0.0.1:18787/owner | jq -e '.completed == true' >/dev/null", "curl -fsS http://127.0.0.1:18787/owner | jq -e '.running == false' >/dev/null")
            execute(script, 0)
            execute((ROOT / 'tests/fixtures/deepen-locking/087-legacy-check.sh').read_text(), 0)
            after = execute(check, 1)
            assert '[DQ:locking_owner]' in after.stdout
            owner = json.loads(execute('curl -fsS http://127.0.0.1:18787/owner', 0).stdout)
            assert owner['exit'] == 0 and not owner['completed'] and owner['stderr']
            log['native_exit_zero_does_not_prove_unlock'] = owner
        else:
            # Owner-only repair cannot recover the missing binding.
            execute('handle=$(curl -fsS http://127.0.0.1:18787/owner | jq -r .handle)\ncurl -fsS -H "Content-Type: application/json" -d "{\\\"handle\\\":\\\"$handle\\\"}" http://127.0.0.1:18787/owner/finish\nfor attempt in $(seq 1 100); do curl -fsS http://127.0.0.1:18787/owner | jq -e .completed >/dev/null && break; sleep .1; done\ntofu state pull > before-recovery.tfstate', 0)
            assert execute('tofu plan -input=false -detailed-exitcode -no-color').returncode == 2
            # Ordinary apply conflicts with the already healthy physical object.
            assert execute('tofu apply -input=false -auto-approve -no-color').returncode != 0
            # Blindly pushing the whole genuine checkpoint drops newer progress.
            execute('tofu state push -force errored.tfstate', 0)
            after = execute(check, 1)
            assert '[DQ:locking_progress]' in after.stdout
            execute('tofu state push -force before-recovery.tfstate', 0)
            # The fixture is now restored for the method-neutral reference path.
            execute((ROOT / 'solutions/087/0.sh').read_text(), 0)
            execute(check, 0)
            execute('printf "\\n" >> errored.tfstate', 0)
            assert '[DQ:locking_checkpoint]' in execute(check, 1).stdout
            log['newer_work_and_original_binding_recovered'] = True
        log['result'] = 'PASS'
    finally:
        try:
            runtime.teardown(run)
            log['teardown'] = 'PASS'
        finally:
            (folder / ('087-owner.json' if unsafe_owner else '087-state.json')).write_text(json.dumps(log, indent=2) + '\n')
