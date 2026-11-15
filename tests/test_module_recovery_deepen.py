"""092: recover modules without rolling back independent current state."""

import copy
import hashlib
import json
import os
import secrets
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime
from test_opentofu_rigid_checks import objective, python_source


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def fixtures():
    def record(kind, identity, module=None, name='kept'):
        value = {'type': kind, 'name': name, 'mode': 'managed', 'instances': [{'attributes': {'id': identity}}]}
        if module is not None:
            value['module'] = module
        return value
    root = {'lineage': 'root-original', 'serial': 5, 'resources': [record('local_file', 'ledger-original', 'module.station', 'ledger')]}
    target = {'lineage': 'infra-original', 'serial': 2, 'resources': [
        record('docker_container', 'container-original', 'module.fabric'),
        record('docker_network', 'network-original', 'module.fabric'),
        record('docker_volume', 'volume-original', 'module.fabric'),
        record('terraform_data', 'progress-original', name='progress'),
    ]}
    root_backup = copy.deepcopy(root)
    root_backup['serial'] = 4
    root_backup['resources'][0]['module'] = 'module.orphan'
    infra_backup = copy.deepcopy(target)
    infra_backup['serial'] = 1
    infra_backup['resources'] = [copy.deepcopy(target['resources'][-1])]
    target['resources'][-1]['instances'][0]['attributes'].update(input={'value': 'completed-work', 'type': 'string'}, output={'value': 'completed-work', 'type': 'string'})
    data = b'north-92\nsequence=000007\n'
    facts = {'container_id': 'container-original', 'network_id': 'network-original', 'volume_name': 'volume-original', 'progress_id': 'progress-original', 'volume_created_at': '2026-11-15T00:00:00Z', 'data_sha256': hashlib.sha256(data).hexdigest(), 'root_lineage': 'root-original', 'infra_lineage': 'infra-original', 'root_serial': 4, 'infra_serial': 1, 'root_backup_sha256': canonical(root_backup), 'infra_backup_sha256': canonical(infra_backup)}
    facts['progress_input'] = {'value': 'completed-work', 'type': 'string'}
    facts['progress_output'] = {'value': 'completed-work', 'type': 'string'}
    worker = {'Id': 'container-original', 'State': {'Running': True}, 'NetworkSettings': {'Networks': {'arbitrary-name': {'NetworkID': 'network-original'}}}, 'Mounts': [{'Type': 'volume', 'Name': 'volume-original', 'Destination': '/data'}]}
    volume = {'Name': 'volume-original', 'CreatedAt': facts['volume_created_at']}
    output = {'container_id': 'container-original', 'network_id': 'network-original', 'volume_name': 'volume-original'}
    def plan(state):
        rows = []
        for r in state['resources']:
            kind = r['type']
            address = ((r['module'] + '.') if r.get('module') else '') + kind + '.' + r['name']
            identity = r['instances'][0]['attributes']['id']
            rows.append({'address': address, 'mode': 'managed', 'type': kind, 'change': {'actions': ['no-op'], 'before': {'id': identity}, 'after': {'id': identity}}})
        return {'resource_changes': rows}
    return facts, root, target, root_backup, infra_backup, worker, volume, output, data, plan(root), plan(target)


def run_probe(monkeypatch, tmp_path, index, variant):
    facts, root, target, root_backup, infra_backup, worker, volume, output, data, root_plan, infra_plan = fixtures()
    if variant == 'lost-newer-work':
        target['resources'].pop()
    elif variant == 'progress-content':
        target['resources'][-1]['instances'][0]['attributes']['input'] = {'value': 'overwritten', 'type': 'string'}
    elif variant == 'nested-module':
        for row in target['resources'][:3]:
            row['module'] = 'module.fabric.module.recovered'
        for row in infra_plan['resource_changes'][:3]:
            row['address'] = row['address'].replace('module.fabric.', 'module.fabric.module.recovered.')
    elif variant == 'progress-renamed':
        target['resources'][-1]['name'] = 'retained'
        infra_plan['resource_changes'][-1]['address'] = 'terraform_data.retained'
    elif variant == 'replaced-binding':
        target['resources'][0]['instances'][0]['attributes']['id'] = 'replacement'
    elif variant == 'wrong-state-boundary':
        target['resources'][0]['module'] = 'module.foreign'
    elif variant == 'extra-managed':
        target['resources'].append(copy.deepcopy(target['resources'][0]))
    elif variant == 'data-only-binding':
        target['resources'][0]['mode'] = 'data'
    elif variant == 'changed-root-id':
        root['resources'][0]['instances'][0]['attributes']['id'] = 'replacement'
    elif variant == 'root-lineage':
        root['lineage'] = 'replacement'
    elif variant == 'infra-lineage':
        target['lineage'] = 'root-original'
    elif variant == 'rolled-back':
        target['serial'] = 0
    elif variant == 'boolean-serial':
        target['serial'] = True
    elif variant == 'stopped':
        worker['State']['Running'] = False
    elif variant == 'detached-network':
        worker['NetworkSettings']['Networks'] = {}
    elif variant == 'wrong-volume':
        worker['Mounts'][0]['Name'] = 'replacement'
    elif variant == 'recreated-volume':
        volume['CreatedAt'] = '2026-11-15T00:01:00Z'
    elif variant == 'data-crlf':
        data = data.replace(b'\n', b'\r\n')
    elif variant == 'output-id':
        output['container_id'] = 'replacement'
    elif variant == 'stale-root-backup':
        root_backup['serial'] = 3
    elif variant == 'older-infra-backup':
        infra_backup['resources'] = []
    elif variant == 'plan-replace':
        infra_plan['resource_changes'][0]['change']['actions'] = ['delete', 'create']
    elif variant == 'plan-id':
        infra_plan['resource_changes'][0]['change']['after']['id'] = 'replacement'
    elif variant == 'plan-state-boundary':
        infra_plan['resource_changes'][0]['address'] = 'module.foreign.docker_container.worker'
    elif variant == 'plan-extra':
        infra_plan['resource_changes'].append(copy.deepcopy(infra_plan['resource_changes'][0]))
    elif variant == 'root-plan-id':
        root_plan['resource_changes'][0]['change']['before']['id'] = 'replacement'
    elif variant == 'readonly-data':
        infra_plan['resource_changes'].append({'mode': 'data', 'change': {'actions': ['read']}})
        target['resources'].append({'mode': 'data', 'type': 'docker_network', 'instances': []})
    elif variant == 'renamed':
        for row in infra_plan['resource_changes'][:3]:
            row['address'] = row['address'].rsplit('.', 1)[0] + '.recovered'
        for row in target['resources'][:3]:
            row['name'] = 'recovered'
    monkeypatch.chdir(tmp_path)
    (tmp_path / 'infra').mkdir()
    for name, value in [('before-recovery.tfstate', root_backup), ('infra/before-recovery.tfstate', infra_backup), ('recovery-plan.json', root_plan), ('infra/recovery-plan.json', infra_plan)]:
        (tmp_path / name).write_text(json.dumps(value))
    original_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == '/run/dq/facts/0/recovery-identities.json':
            return json.dumps(facts)
        if str(path) == '/run/dq/facts/0/original-id':
            return 'ledger-original\n'
        return original_read(path, *args, **kwargs)

    def cli(argv, **kwargs):
        value = ''
        code = 0
        if argv == ['tofu', 'state', 'pull']:
            value = json.dumps(root)
        elif argv == ['tofu', '-chdir=infra', 'state', 'pull']:
            value = json.dumps(target)
            if variant == 'target-cli-failed':
                code = 1
        elif argv[:3] == ['docker', 'volume', 'inspect']:
            value = json.dumps([volume])
        elif argv[:2] == ['docker', 'inspect']:
            value = json.dumps([worker])
        elif argv[:2] == ['docker', 'exec']:
            value = data
        elif argv[:3] == ['tofu', '-chdir=infra', 'output']:
            value = json.dumps(output)
        else:
            assert argv[:3] == ['tofu', '-chdir=infra', 'plan']
            code = 2 if variant == 'pending-target-plan' else 0
        return SimpleNamespace(returncode=code, stdout=value)

    monkeypatch.setattr(Path, 'read_text', read)
    monkeypatch.setattr(subprocess, 'run', cli)
    code = python_source(objective('092', index))
    try:
        exec(compile(code, '092-shipped-recovery', 'exec'), {'__name__': '__main__'})
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize('variant', ['reference', 'renamed', 'readonly-data', 'nested-module', 'progress-renamed', 'plan-replace', 'plan-id', 'plan-state-boundary', 'plan-extra', 'root-plan-id'])
def test_saved_plans_keep_original_bindings(monkeypatch, tmp_path, variant):
    assert run_probe(monkeypatch, tmp_path, 4, variant) == (0 if variant in ['reference', 'renamed', 'readonly-data', 'nested-module', 'progress-renamed'] else 1)


@pytest.mark.parametrize('variant', ['reference', 'renamed', 'readonly-data', 'nested-module', 'progress-renamed', 'progress-content', 'lost-newer-work', 'replaced-binding', 'wrong-state-boundary', 'extra-managed', 'data-only-binding', 'changed-root-id', 'root-lineage', 'infra-lineage', 'rolled-back', 'boolean-serial', 'stopped', 'detached-network', 'wrong-volume', 'recreated-volume', 'data-crlf', 'output-id', 'stale-root-backup', 'older-infra-backup', 'target-cli-failed', 'pending-target-plan'])
def test_both_states_and_real_identity_data(monkeypatch, tmp_path, variant):
    assert run_probe(monkeypatch, tmp_path, 5, variant) == (0 if variant in ['reference', 'renamed', 'readonly-data', 'nested-module', 'progress-renamed'] else 1)


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
@pytest.mark.parametrize('variant', ['old-minimal', 'whole-backup', 'data-bytes', 'progress-content'])
def test_native_module_recovery_shortcuts(variant):
    catalog = Catalog()
    runtime = Runtime(ROOT / '.state/runtime')
    run = {'id': secrets.token_hex(12), 'level': 92}
    folder = Path(os.environ.get('DQ_DEEPEN_EVIDENCE', ROOT / 'artifacts/module-recovery-shortcuts'))
    folder.mkdir(parents=True, exist_ok=True)
    log = {'quest': 92, 'variant': variant}

    def execute(script, expected=None):
        result = runtime.exec(run, 'set -euo pipefail\ncd ~/quest\n' + script, check=False, timeout=180)
        log.setdefault('commands', []).append({'script': script, 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
        if expected is not None:
            assert result.returncode == expected, result.stdout + result.stderr
        return result

    try:
        runtime.create(run)
        execute(catalog.script(92, 0, 'setup'), 0)
        runtime.capture_facts(dict(run, stage=0), catalog.quests[92]['immutable'][0])
        solution = (ROOT / 'solutions/092/0.sh').read_text()
        # The supplied caller is already production topology: constructing its
        # missing module alone is not the additional state recovery requirement.
        constructor = solution[:solution.index('tofu state pull > before-recovery.tfstate')]
        execute(constructor, 0)
        check = catalog.script(92, 0, 'check')
        if variant == 'old-minimal':
            execute('tofu state pull > before-recovery.tfstate\ntofu -chdir=infra state pull > infra/before-recovery.tfstate', 0)
            execute((ROOT / 'tests/fixtures/deepen-module-recovery/092.sh').read_text(), 0)
            execute('tofu -chdir=infra plan -input=false -no-color -out=recovery.plan\ntofu -chdir=infra show -json recovery.plan > infra/recovery-plan.json', 0)
            execute((ROOT / 'tests/fixtures/deepen-module-recovery/092-legacy-check.sh').read_text(), 0)
            after = execute(check, 1)
            assert '[DQ:recovery_target]' in after.stdout and '[DQ:recovery_plans]' in after.stdout
            log['whole_old_quest_after_constructor_and_old_fix'] = 'PASS; new state bindings still missing'
        else:
            execute(solution, 0)
            execute(check, 0)
            if variant == 'whole-backup':
                # Standard lineage protection rejects the old main backup at
                # the independent target. Forcing it in this disposable bay
                # demonstrates the actual loss that the guard prevents.
                assert execute('tofu -chdir=infra state push ../safe-state.json').returncode != 0
                execute('tofu -chdir=infra state push -force ../safe-state.json', 0)
                after = execute(check, 1)
                assert '[DQ:recovery_lineage]' in after.stdout and '[DQ:recovery_target]' in after.stdout
            elif variant == 'progress-content':
                execute("sed -i 's/split-completed-before-recovery/overwritten/' infra/main.tf\ntofu -chdir=infra apply -input=false -auto-approve -no-color\ntofu plan -input=false -detailed-exitcode -no-color\ntofu -chdir=infra plan -input=false -detailed-exitcode -no-color", 0)
                observed = json.loads(execute('tofu -chdir=infra state pull', 0).stdout)
                facts = json.loads(execute('cat /run/dq/facts/0/recovery-identities.json', 0).stdout)
                progress = next(r for r in observed['resources'] if r['type'] == 'terraform_data')['instances'][0]['attributes']
                assert progress['id'] == facts['progress_id'] and progress['input'] != facts['progress_input']
                execute((ROOT / 'tests/fixtures/deepen-module-recovery/092-legacy-check.sh').read_text(), 0)
                assert '[DQ:recovery_target]' in execute(check, 1).stdout
                log['same_uuid_and_two_empty_plans_do_not_preserve_completed_data'] = True
            else:
                execute("docker exec rail-ledger-worker sh -c 'printf \"north-92\\r\\nsequence=000007\\r\\n\" > /data/ledger'\ntofu plan -input=false -detailed-exitcode -no-color\ntofu -chdir=infra plan -input=false -detailed-exitcode -no-color", 0)
                execute((ROOT / 'tests/fixtures/deepen-module-recovery/092-legacy-check.sh').read_text(), 0)
                after = execute(check, 1)
                assert '[DQ:recovery_data]' in after.stdout
                log['two_empty_plans_do_not_prove_volume_bytes'] = True
        log['result'] = 'PASS'
    finally:
        try:
            runtime.teardown(run)
            log['teardown'] = 'PASS'
        finally:
            (folder / ('092-' + variant + '.json')).write_text(json.dumps(log, indent=2) + '\n')
