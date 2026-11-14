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
@pytest.mark.parametrize('number', [33, 53, 56, 59, 64, 71, 76])
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
        elif number in (64, 76):
            assert fixed.returncode != 0, 'The old root-only repair must leave the required module construction incomplete'
            runtime.exec(run, (ROOT/f'solutions/{number:03}/0.sh').read_text(), timeout=240)
            assert runtime.exec(run, check, check=False, timeout=90).returncode == 0
            if number == 64:
                mutation=r'''import re
from pathlib import Path
p=Path('modules/station/main.tf');s=p.read_text();s,n=re.subn(r'(region\s*=\s*)var\.region',r'\1"north"',s);assert n==1;p.write_text(s)
'''
                marker='[DQ:fanout_contract]'
            else:
                mutation='''from pathlib import Path
p=Path('branches.tf');s=p.read_text();assert '${module.south.route}|${module.east.route}' in s;s=s.replace('${module.south.route}|${module.east.route}','${var.hub}:north:south|${var.hub}:east');p.write_text(s)
'''
                marker='[DQ:dag_dependencies]'
            runtime.exec(run, "cd ~/quest\npython3 - <<'MUTATE'\n"+mutation+"MUTATE\n")
            # Keep the negative fixture valid and converged at its default input:
            # only the required propagation/dependency property is broken.
            runtime.exec(run, 'cd ~/quest\ntofu validate -no-color\ntofu plan -input=false -no-color -detailed-exitcode\n', timeout=90)
            coupled=runtime.exec(run, check, check=False, timeout=90)
            assert coupled.returncode != 0 and marker in coupled.stdout
            log['default_only_or_disconnected_graph']='rejected'
            log['coupled_diagnostic']=coupled.stdout
            if number == 76:
                mutation=r'''from pathlib import Path
p=Path('branches.tf');s=p.read_text();assert '${var.hub}:north:south|${var.hub}:east' in s;p.write_text(s.replace('${var.hub}:north:south|${var.hub}:east','${module.south.route}|${module.east.route}'))
p=Path('main.tf');s=p.read_text();assert s.count('output "routes"')==1;s=s[:s.index('output "routes"')]+'output "routes" {\n value = { north = "dispatch:north", south = "dispatch:north:south" }\n}\n';p.write_text(s)
'''
                runtime.exec(run, "cd ~/quest\npython3 - <<'MUTATE'\n"+mutation+"MUTATE\ntofu validate -no-color\ntofu plan -input=false -no-color -detailed-exitcode\n", timeout=90)
                constant=runtime.exec(run, check, check=False, timeout=90)
                assert constant.returncode != 0 and '[DQ:dag_contract]' in constant.stdout
                log['constant_default_output']='rejected'
        elif number == 71:
            assert fixed.returncode == 0, 'The old apply must execute before replacement-identity rejection'
            assert '[DQ:recovery_bindings]' in after.stdout
            # An older whole checkpoint also loses the newer completed progress binding.
            runtime.exec(run, 'cd ~/quest\ntofu state push -force recovery-checkpoint.tfstate\n', timeout=60)
            again=runtime.exec(run, old, check=False, timeout=180)
            assert again.returncode == 0
            rollback=runtime.exec(run, check, check=False, timeout=90)
            assert rollback.returncode != 0 and '[DQ:recovery_bindings]' in rollback.stdout
            log['whole_checkpoint_restore']='rejected'
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


@pytest.mark.parametrize('variant', ['valid', 'replaced', 'missing', 'edited-addresses', 'unrelated-managed', 'readonly-data'])
def test_064_preserves_each_original_identity(monkeypatch, tmp_path, variant):
    file_addresses = ['module.station["depot"].module.notice.local_file.route', 'module.station["junction"].module.notice.local_file.route']
    text = '\n'.join(file_addresses) + '\n'
    (tmp_path/'original-addresses').write_text('edited\n' if variant == 'edited-addresses' else text)
    (tmp_path/'frozen-original-addresses').write_text(text)
    identities = {f'module.station["{name}"].terraform_data.identity': name+'-id' for name in ['depot', 'junction']}
    (tmp_path/'station-identities.json').write_text(json.dumps(identities))
    rows = [('module.station["'+name+'"].module.notice', resource(name+'.txt', address)) for name,address in zip(['depot','junction'],file_addresses)]
    for i,(address,identity) in enumerate(identities.items()):
        if variant == 'missing' and i == 0:
            continue
        rows.append(('module.station', {'address':address,'mode':'managed','type':'terraform_data','values':{'id':'new-id' if variant=='replaced' and i==0 else identity}}))
    if variant == 'unrelated-managed':
        rows.append((None, resource('unrelated.txt')))
    if variant == 'readonly-data':
        rows.append((None, {'address':'data.local_file.inspect','mode':'data','type':'local_file','values':{}}))
    assert run_python(monkeypatch,tmp_path,'064',2,tag='DQ_FANOUT_IDENTITIES',document=state(*rows)) == (0 if variant in ['valid','readonly-data'] else 1)


@pytest.mark.parametrize('variant', ['valid','replaced','missing','unrelated'])
def test_071_operation_bindings_are_retained(monkeypatch,tmp_path,variant):
    for name in ['north','south']:
        (tmp_path/(name+'.txt')).write_text('route')
    rows=[(None,resource(name+'.txt','local_file.'+name)) for name in ['north','south']]
    for name in ['guardian','progress']:
        if variant=='missing' and name=='guardian':
            continue
        rows.append((None,{'address':'terraform_data.'+name,'mode':'managed','type':'terraform_data','values':{'id':'replacement' if variant=='replaced' and name=='guardian' else name+'-original'}}))
    if variant=='unrelated':
        rows.append((None,resource('extra.txt')))
    assert run_python(monkeypatch,tmp_path,'071',2,document=state(*rows)) == (0 if variant=='valid' else 1)


@pytest.mark.parametrize('variant',['valid','changed-checkpoint','newer-backup','wrong-lineage','lost-progress','old-checkpoint'])
def test_071_backup_preserves_the_newer_partial_checkpoint(monkeypatch,tmp_path,variant):
    import hashlib
    checkpoint=b'trusted snapshot bytes\n'
    (tmp_path/'recovery-checkpoint.tfstate').write_bytes(checkpoint+(b'x' if variant=='changed-checkpoint' else b''))
    identities={'local_file.north':'original','terraform_data.progress':'progress-original'}
    facts={'checkpoint_sha256':hashlib.sha256(checkpoint).hexdigest(),'partial':{'lineage':'owned-lineage','serial':4,'identities':identities}}
    (tmp_path/'state-identities.json').write_text(json.dumps(facts))
    backup={'lineage':'wrong' if variant=='wrong-lineage' else 'owned-lineage','serial':5 if variant=='newer-backup' else 4,'resources':[{'mode':'managed','type':key.split('.')[0],'name':key.split('.')[1],'instances':[{'attributes':{'id':value}}]} for key,value in identities.items()]}
    if variant=='lost-progress':
        backup['resources'].pop()
    if variant=='old-checkpoint':
        backup['resources'][1]['name']='guardian'
        backup['resources'][1]['instances'][0]['attributes']['id']='guardian-original'
    (tmp_path/'before-recovery.tfstate').write_text(json.dumps(backup))
    assert run_python(monkeypatch,tmp_path,'071',3,tag='DQ_RECOVERY_BACKUP') == (0 if variant=='valid' else 1)
