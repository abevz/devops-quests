"""dq-82: real old-fix regressions and retained module-consumer identity."""

import json
import os
import secrets
from pathlib import Path

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime
from test_opentofu_rigid_checks import resource, run_python, state


@pytest.mark.parametrize('variant', ['valid', 'wrong-id', 'missing-identity', 'same-module', 'wrong-payload', 'malformed'])
def test_053_preserves_the_distinct_original_consumer(monkeypatch, tmp_path, variant):
    (tmp_path/'north.txt').write_text('north-ready')
    (tmp_path/'delivered.txt').write_text('north-ready')
    consumer = 'module.notice' if variant == 'same-module' else 'module.dispatch'
    identity = {'address': consumer+'.terraform_data.receipt', 'type': 'terraform_data',
                'mode': 'managed', 'values': {'id': 'consumer-original', 'output': 'north-ready'}}
    if variant == 'wrong-id':
        identity['values']['id'] = 'replacement'
    elif variant == 'wrong-payload':
        identity['values']['output'] = 'foreign'
    elif variant == 'malformed':
        identity['values'] = None
    records = [('module.notice', resource('north.txt')),
               (consumer, resource('delivered.txt', consumer+'.local_file.receipt'))]
    if variant != 'missing-identity':
        records.append((consumer, identity))
    assert run_python(monkeypatch, tmp_path, '053', document=state(*records)) == (0 if variant == 'valid' else 1)


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
@pytest.mark.parametrize('number', [33, 53, 56, 59])
def test_old_minimal_opentofu_fix_does_not_complete(number):
    catalog = Catalog()
    runtime = Runtime(ROOT/'.state/runtime')
    run = {'id': secrets.token_hex(12), 'level': number}
    folder = Path(os.environ.get('DQ_DEEPEN_EVIDENCE', ROOT/'artifacts/opentofu-shortcuts'))
    folder.mkdir(parents=True, exist_ok=True)
    log = {'quest': number, 'old_source': 'ae87ab3'}
    try:
        runtime.create(run)
        runtime.exec(run, 'set -euo pipefail\ncd ~/quest\n'+catalog.script(number, 0, 'setup'), timeout=240)
        facts = catalog.quests[number].get('immutable', {}).get(0, [])
        if facts:
            runtime.capture_facts(dict(run, stage=0), facts)
        check = catalog.script(number, 0, 'check')
        assert runtime.exec(run, check, check=False, timeout=90).returncode != 0
        old = (ROOT/f'tests/fixtures/deepen-opentofu/{number:03}.sh').read_text()
        fixed = runtime.exec(run, old, check=False, timeout=180)
        after = runtime.exec(run, check, check=False, timeout=90)
        assert after.returncode != 0, 'Audited minimal fix completed the deepened quest'
        log.update(initial='FAIL as expected', old_fix_exit=fixed.returncode,
                   old_fix_stdout=fixed.stdout, old_fix_stderr=fixed.stderr,
                   after='FAIL as expected', diagnostics=after.stdout)
        if number == 33:
            assert fixed.returncode == 0, 'Old map expansion must execute before identity/content rejection'
            assert '[DQ:condition_' in after.stdout
        elif number == 53:
            assert fixed.returncode != 0, 'The old producer-only fix must leave the downstream contract broken'
        elif number == 56:
            assert fixed.returncode == 0, 'The old numeric validator must apply before typed contract rejection'
            assert '[DQ:capacity_contract]' in after.stdout
        else:
            assert fixed.returncode == 0, 'The old one-resource move must apply before UUID-preservation rejection'
            assert '[DQ:move_identity]' in after.stdout
    except Exception as error:
        log['error'] = str(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            log['teardown'] = 'PASS'
        finally:
            (folder/f'{number:03}.json').write_text(json.dumps(log, indent=2)+'\n')
