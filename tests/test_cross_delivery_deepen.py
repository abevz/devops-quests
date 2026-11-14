"""081: current producer identity must reach independently managed consumers."""

import json
import os
import secrets
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime
from test_opentofu_rigid_checks import objective, python_source, resource, state


def agreement(release='release-81', identity='producer-original'):
    return {'release': release, 'producer_id': identity,
            'targets': {host: {'target': host, 'release': release, 'producer_id': identity}
                        for host in ['app1', 'app2', 'app3']}}


def producer_state(identity='producer-original', release='release-81'):
    return state((None, resource('release.txt', 'local_file.release', content=release+'\n')),
                 (None, {'address': 'terraform_data.producer', 'mode': 'managed',
                         'type': 'terraform_data', 'values': {'id': identity}}))


def check_contract(monkeypatch, tmp_path, stage, variant):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv('DQ_NAMESPACE', 'dq-synthetic')
    original_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == '/run/dq/facts/0/producer-identity.json':
            if variant == 'missing-fact':
                raise FileNotFoundError(path)
            return json.dumps('producer-original')
        if str(path) == '/run/dq/facts/0/delivery-schema.json':
            return json.dumps({'input_cases': ['release-81', 'release-canary']})
        return original_read(path, *args, **kwargs)

    planned_release = 'release-81'

    def cli(argv, **kwargs):
        nonlocal planned_release
        output = ''
        if argv[0] == 'tofu':
            if argv[1] == 'plan':
                for i, part in enumerate(argv):
                    if part == '-var':
                        planned_release = argv[i+1].split('=', 1)[1]
            elif argv[1] == 'output':
                value = agreement()
                if variant == 'stale-output':
                    value['producer_id'] = 'old-export'
                elif variant == 'wrong-target':
                    value['targets']['app1']['target'] = 'app2'
                output = json.dumps(value)
            elif len(argv) == 3:
                output = json.dumps(producer_state('replacement' if variant == 'replaced-producer' else 'producer-original'))
            else:
                value = agreement('release-81' if variant == 'default-only' else planned_release)
                document = producer_state(release=planned_release)
                document['planned_values'] = document.pop('values')
                document['planned_values']['outputs'] = {'delivery': {'value': value}}
                output = json.dumps(document)
        elif argv[0] == 'ssh':
            host = argv[-2].split('@', 1)[1].removesuffix('-synthetic')
            value = agreement()['targets'][host]
            if variant == 'stale-receipt' and host == 'app2':
                value['producer_id'] = 'old-export'
            if variant == 'wrong-receipt-target' and host == 'app2':
                value['target'] = 'app1'
            mode = '600' if variant == 'receipt-mode' and host == 'app2' else '644'
            output = json.dumps(value, indent=2)+'\n'+mode+'\n'
        else:
            assert argv[0] == 'kubectl' and ['-c', 'worker'] == argv[argv.index('-c'):argv.index('-c')+2]
            value = agreement()
            if variant == 'stale-process':
                value['producer_id'] = 'old-export'
            output = '{invalid' if variant == 'malformed-process' else json.dumps(value)
        code = 1 if variant == 'cli-failed' else 0
        if kwargs.get('check') and code:
            raise subprocess.CalledProcessError(code, argv)
        return SimpleNamespace(returncode=code, stdout=output, stderr='')

    monkeypatch.setattr(Path, 'read_text', read)
    monkeypatch.setattr(subprocess, 'run', cli)
    tag = ['DQ_DELIVERY_PRODUCER', 'DQ_DELIVERY_FLEET', 'DQ_DELIVERY_RELAY'][stage]
    code = python_source(objective('081', 0, stage), tag)
    try:
        exec(compile(code, '081-current-contract', 'exec'), {'__name__': '__main__'})
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize('stage', [0, 1, 2])
@pytest.mark.parametrize('variant', ['valid', 'missing-fact', 'replaced-producer', 'stale-output', 'wrong-target', 'cli-failed'])
def test_current_producer_is_required_at_every_stage(monkeypatch, tmp_path, stage, variant):
    assert check_contract(monkeypatch, tmp_path, stage, variant) == (0 if variant == 'valid' else 1)


def test_default_only_output_is_not_forwarding(monkeypatch, tmp_path):
    assert check_contract(monkeypatch, tmp_path, 0, 'default-only') == 1


@pytest.mark.parametrize('stage', [1, 2])
@pytest.mark.parametrize('variant', ['stale-receipt', 'wrong-receipt-target', 'receipt-mode'])
def test_each_fleet_receipt_remains_current_at_completion(monkeypatch, tmp_path, stage, variant):
    assert check_contract(monkeypatch, tmp_path, stage, variant) == 1


@pytest.mark.parametrize('variant', ['stale-process', 'malformed-process'])
def test_relay_contract_is_read_from_the_running_worker(monkeypatch, tmp_path, variant):
    assert check_contract(monkeypatch, tmp_path, 2, variant) == 1


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
def test_old_minimal_delivery_fixes_and_stale_exports_do_not_complete():
    catalog = Catalog()
    runtime = Runtime(ROOT/'.state/runtime')
    run = {'id': secrets.token_hex(12), 'level': 81}
    folder = Path(os.environ.get('DQ_DEEPEN_EVIDENCE', ROOT/'artifacts/cross-delivery-shortcuts'))
    folder.mkdir(parents=True, exist_ok=True)
    log = {'quest': 81, 'old_source': 'ae87ab32c5c4c8343cc56b33dc3828e691485224', 'stages': []}
    try:
        runtime.create(run)
        for stage in range(3):
            runtime.exec(run, 'set -euo pipefail\ncd ~/quest\n'+catalog.script(81, stage, 'setup'), timeout=240)
            facts = catalog.quests[81].get('immutable', {}).get(stage, [])
            if facts:
                runtime.capture_facts(dict(run, stage=stage), facts)
            check = catalog.script(81, stage, 'check')
            assert runtime.exec(run, check, check=False, timeout=120).returncode != 0
            old = (ROOT/f'tests/fixtures/deepen-cross-delivery/081-{stage}.sh').read_text()
            attempted = runtime.exec(run, old, check=False, timeout=180)
            assert attempted.returncode == 0, attempted.stdout+attempted.stderr
            after = runtime.exec(run, check, check=False, timeout=120)
            assert after.returncode != 0
            marker = ['delivery_producer', 'delivery_fleet', 'delivery_relay'][stage]
            assert '[DQ:'+marker+']' in after.stdout, after.stdout
            runtime.exec(run, (ROOT/f'solutions/081/{stage}.sh').read_text(), timeout=240)
            solved = runtime.exec(run, check, check=False, timeout=120)
            assert solved.returncode == 0, solved.stdout+solved.stderr
            log['stages'].append({'stage': stage, 'initial': 'FAIL as expected',
                                  'old_fix_exit': attempted.returncode, 'after_old_fix': after.stdout,
                                  'solution': 'PASS'})
            if stage == 0:
                runtime.exec(run, r'''cd ~/quest
cp modules/delivery/main.tf /tmp/delivery-working.tf
python3 - <<'MUTATE'
from pathlib import Path
import re
p=Path('modules/delivery/main.tf');s=p.read_text();s,count=re.subn(r'\brelease\s*=\s*var\.release\b','release = "release-81"',s);assert count==2;p.write_text(s)
MUTATE
tofu validate -no-color
tofu plan -input=false -detailed-exitcode -no-color
''', timeout=90)
                invalid = runtime.exec(run, check, check=False, timeout=120)
                assert invalid.returncode != 0 and '[DQ:delivery_producer]' in invalid.stdout
                log['default_only'] = invalid.stdout
                runtime.exec(run, 'cd ~/quest\ncp /tmp/delivery-working.tf modules/delivery/main.tf\n')
            if stage in (1, 2):
                # Keep the original files, mode and HTTP correct; only one receipt is stale.
                runtime.exec(run, '''cd ~/quest
python3 - <<'STALE_RECEIPT'
import json,subprocess
entry={'target':'app2','release':'release-81','producer_id':'stale'}
args={'dest':'/srv/site/delivery.json','content':json.dumps(entry),'mode':'0644'}
subprocess.run(['ansible','app2','-m','ansible.builtin.copy','-a',json.dumps(args)],check=True)
STALE_RECEIPT
''', timeout=90)
                legacy=catalog.quests[81]['stages'][stage]['objectives'][1]['check']
                assert runtime.exec(run,'set -euo pipefail\ncd ~/quest\n'+legacy,check=False,timeout=30).returncode==0
                invalid = runtime.exec(run, check, check=False, timeout=120)
                assert invalid.returncode != 0 and '[DQ:delivery_'+('fleet' if stage == 1 else 'relay')+']' in invalid.stdout
                log['stale_receipt_stage_'+str(stage)] = invalid.stdout
                runtime.exec(run, (ROOT/'solutions/081/1.sh').read_text(), timeout=180)
                assert runtime.exec(run, check, check=False, timeout=120).returncode == 0
    finally:
        try:
            runtime.teardown(run)
            log['teardown'] = 'PASS'
        finally:
            (folder/'081.json').write_text(json.dumps(log, ensure_ascii=False, indent=2)+'\n')
