"""Run the shipped OpenTofu predicates against qualified CLI JSON/graph layouts.

These are checker tests, not a second implementation of the predicates. Saved
plans use planned_values; state uses values, as emitted by OpenTofu 1.13.
"""
import copy
import json
import re
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def objective(quest, index=0, stage=0):
    return yaml.safe_load((ROOT / 'quests' / quest / 'quest.yaml').read_text())['stages'][stage]['objectives'][index]['check']


def python_source(check, tag='DQ_PROPERTY'):
    match = re.search(r"python3 -I - <<'" + tag + "'\n(.*?)\n" + tag + r'(?:\n|$)', check, re.S)
    assert match, 'Execute the actual isolated Python heredoc from the shipped check'
    return match[1]


def resource(filename, address='local_file.notice', module=None, **values):
    return {'address': address, 'mode': 'managed', 'type': 'local_file', 'values': {'filename': filename, 'content': 'north-ready', 'id': 'original', **values}}


def state(*records, section='values'):
    root = {'resources': [], 'child_modules': []}
    for module, record in records:
        if module:
            root['child_modules'].append({'address': module, 'resources': [record]})
        else:
            root['resources'].append(record)
    return {section: {'root_module': root}}


def run_python(monkeypatch, tmp_path, quest, index=0, *, document=None, graph='', plans=None, tag='DQ_PROPERTY', returncode=0):
    monkeypatch.chdir(tmp_path)
    original_read = Path.read_text

    def read(path, *args, **kwargs):
        if str(path) == '/run/dq/facts/0/original-north-id':
            return 'original\n'
        return original_read(path, *args, **kwargs)

    def cli(argv, **kwargs):
        assert argv[0] == 'tofu', argv
        if argv[1] == 'graph':
            return SimpleNamespace(returncode=returncode, stdout=graph, stderr='')
        if argv[1] in ('show', 'output'):
            return SimpleNamespace(returncode=returncode, stdout=json.dumps(document), stderr='')
        assert argv[1] == 'plan', argv
        if plans:
            return plans(argv)
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    monkeypatch.setattr(Path, 'read_text', read)
    monkeypatch.setattr(subprocess, 'run', cli)
    code = python_source(objective(quest, index), tag)
    try:
        exec(compile(code, f'quest-{quest}-objective-{index}', 'exec'), {'__name__': '__main__'})
    except SystemExit as result:
        return result.code or 0
    return 0


@pytest.mark.parametrize('graph,expected', [
    ('digraph { "terraform_data.marker" -> "terraform_data.directory"; }', 0),
    ('digraph { "[root] terraform_data.marker (expand)" -> "terraform_data.bridge"; "terraform_data.bridge" -> "[root] terraform_data.directory (expand)"; }', 0),
    ('digraph { "terraform_data.directory" -> "terraform_data.marker"; }', 1),
    ('digraph { "terraform_data.marker" -> "terraform_data.directory_wrong"; }', 1),
    ('digraph { x [label="terraform_data.marker -> terraform_data.directory"]; }', 1),
    ('digraph { // "terraform_data.marker" -> "terraform_data.directory"\n}', 1),
    ('digraph { "terraform_data.marker" -> "terraform_data.marker"; }', 1),
])
def test_019_dependency_property(monkeypatch, tmp_path, graph, expected):
    assert run_python(monkeypatch, tmp_path, '019', 1, graph=graph) == expected


@pytest.mark.parametrize('quest,filename,module', [('029', 'notice.txt', None), ('053', 'north.txt', 'module.notice'), ('081', 'release.txt', None), ('087', 'notice.txt', None)])
@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-file', 'data-only', 'cli-failed'])
def test_managed_producer_by_file(monkeypatch, tmp_path, quest, filename, module, variant):
    (tmp_path / filename).write_text('north-ready')
    address = 'local_file.notice' if variant == 'reference' else 'local_file.renamed["current"]'
    record = resource(filename if variant != 'wrong-file' else 'other.txt', address)
    if variant == 'equivalent':
        record['values']['filename'] = str(tmp_path / filename)
    if variant == 'data-only':
        record['mode'] = 'data'
    result = run_python(monkeypatch, tmp_path, quest, 1 if quest == '087' else 0, document=state((module, record)), returncode=1 if variant == 'cli-failed' else 0)
    assert result == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('quest,names,index', [('023', ('north.txt', 'south.txt'), 0), ('076', ('north.txt', 'south.txt'), 2), ('071', ('north.txt', 'south.txt'), 2)])
@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-file', 'same-instance', 'extra-resource'])
def test_route_inventory_properties(monkeypatch, tmp_path, quest, names, index, variant):
    for name in names:
        (tmp_path / name).write_text('route')
    records = []
    for i, name in enumerate(names):
        module = None if quest == '071' else f'module.stations[{i}]'
        if variant == 'same-instance':
            module = 'module.same'
        filename = 'other.txt' if variant == 'wrong-file' and i == 1 else name
        if variant == 'equivalent' and filename == name:
            filename = str(tmp_path / name)
        records.append((module, resource(filename, f'{module + "." if module else ""}local_file.route[{i}]')))
    if variant == 'extra-resource':
        records.append((None, resource('unrelated.txt')))
    valid = variant in ('reference', 'equivalent') or (variant == 'extra-resource' and quest == '023') or (variant == 'same-instance' and quest == '071')
    assert run_python(monkeypatch, tmp_path, quest, index, document=state(*records)) == (0 if valid else 1)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-file', 'data-only'])
def test_033_added_route_in_managed_set(monkeypatch, tmp_path, variant):
    records = []
    for i, name in enumerate(('north.txt', 'south.txt', 'east.txt')):
        (tmp_path / name).write_text('open')
        record = resource(name, f'local_file.renamed[{i}]')
        if variant == 'equivalent':
            record['values']['filename'] = str(tmp_path / name)
        if i == 2 and variant == 'wrong-file':
            record['values']['filename'] = 'other.txt'
        if i == 2 and variant == 'data-only':
            record['mode'] = 'data'
        records.append((None, record))
    assert run_python(monkeypatch, tmp_path, '033', 2, document=state(*records)) == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('actions,identity,filename,expected', [
    (['delete', 'create'], 'original', 'ledger.txt', 0),
    (['create', 'delete'], 'original', './ledger.txt', 0),
    (['delete'], 'original', 'ledger.txt', 1),
    (['delete', 'create'], 'other', 'ledger.txt', 1),
    (['delete', 'create'], 'original', 'unrelated.txt', 1),
])
def test_036_replacement_targets_original_ledger(monkeypatch, tmp_path, actions, identity, filename, expected):
    (tmp_path / 'ledger.txt').write_text('revision-36')
    (tmp_path / 'original-id').write_text('original')
    record = resource(filename, 'local_file.renamed')
    record['change'] = {'before': {'filename': filename, 'id': identity}, 'actions': actions}
    (tmp_path / 'rejected-plan.json').write_text(json.dumps({'resource_changes': [record]}))
    assert run_python(monkeypatch, tmp_path, '036') == expected


@pytest.mark.parametrize('text,status,expected', [
    ('departures must be an integer from 1 to 6', 1, 0),
    ('\x1b[31mdepartures must be an integer\x1b[0m\n│ from 1 to 6', 1, 0),
    ('departures must be an integer from 1 to 6', 0, 1),
    ('Some unrelated error', 1, 1),
    ('departures must be an integer from 1 to 60', 1, 1),
])
def test_039_diagnostic_wrap_is_display_only(monkeypatch, tmp_path, text, status, expected):
    seen = []

    def cli(argv):
        seen.append(argv[-1])
        return SimpleNamespace(returncode=status, stdout=text, stderr='')

    assert run_python(monkeypatch, tmp_path, '039', plans=cli) == expected
    if expected == 0:
        assert seen == ['-var=departures=0', '-var=departures=7', '-var=departures=2.5']


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-file', 'extra-output', 'unusable-alias'])
def test_064_output_paths_identify_exact_files(monkeypatch, tmp_path, variant):
    for name in ('depot', 'junction'):
        (tmp_path / (name + '.txt')).write_text('route')
    routes = {'depot': './depot.txt', 'junction': './junction.txt'}
    if variant == 'equivalent':
        routes = {name: str(tmp_path / (name + '.txt')) for name in routes}
    elif variant == 'wrong-file':
        routes['depot'] = 'junction.txt'
    elif variant == 'extra-output':
        routes['other'] = 'depot.txt'
    elif variant == 'unusable-alias':
        routes['depot'] = 'absent/../depot.txt'
    assert run_python(monkeypatch, tmp_path, '064', 5, document=routes) == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'json-alias', 'wrong-content', 'wrong-file', 'missing-instance', 'literal', 'unused-reference', 'wrong-reference', 'source-plan-mismatch'])
def test_064_saved_regional_contract(monkeypatch, tmp_path, variant):
    addresses = ['module.stations["depot"].local_file.route', 'module.stations["junction"].local_file.route']
    (tmp_path / 'original-addresses').write_text('\n'.join(addresses))
    records = [(None, resource('./' + name + '.txt', address, content='north:' + name)) for address, name in zip(addresses, ('depot', 'junction'))]
    expression = 'local.region'
    references = ['local.region']
    locals_block = 'locals { region = "north"\n forward = local.region\n}'
    if variant == 'equivalent':
        expression = 'trimspace(local.forward)'
        references = ['local.forward']
    elif variant == 'literal':
        expression = '"north"'
        references = []
    elif variant == 'unused-reference':
        expression = 'true ? "north" : local.region'
    elif variant == 'wrong-reference':
        locals_block += '\nlocals { unrelated = "north" }'
        expression = 'local.unrelated'
        references = ['local.unrelated']
    elif variant == 'source-plan-mismatch':
        locals_block += '\nlocals { other = local.region }'
        references = ['local.other']
    if variant == 'json-alias':
        references = ['local.forward']
        (tmp_path / 'main.tf.json').write_text(json.dumps({'locals': {'region': 'north', 'forward': '${local.region}'}, 'module': {'stations': {'region': '${local.forward}'}}}))
    else:
        (tmp_path / 'main.tf').write_text(locals_block + '\nmodule "stations" { region = ' + expression + ' }\n')
    if variant == 'equivalent':
        records.reverse()
        for _, record in records:
            record['values']['filename'] = str(tmp_path / Path(record['values']['filename']).name)
            record['values']['content'] += '\n'
    elif variant == 'wrong-content':
        records[0][1]['values']['content'] = 'retired:depot'
    elif variant == 'wrong-file':
        records[0][1]['values']['filename'] = 'other.txt'
    elif variant == 'missing-instance':
        records.pop()
    plan = state(*records, section='planned_values')
    plan['configuration'] = {'root_module': {'module_calls': {'stations': {'expressions': {'region': {'references': references}}}}}}
    (tmp_path / 'fanout-plan.json').write_text(json.dumps(plan))
    assert run_python(monkeypatch, tmp_path, '064') == (0 if variant in ('reference', 'equivalent', 'json-alias') else 1)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'extra-change', 'missing-instance', 'one-sided'])
def test_064_exact_two_replacements_not_metadata_count(monkeypatch, tmp_path, variant):
    addresses = ['module.stations["depot"].local_file.route', 'module.stations["junction"].local_file.route']
    (tmp_path / 'original-addresses').write_text('\n'.join(addresses))
    changes = [dict(resource('', address), change={'actions': ['delete', 'create']}) for address in addresses]
    if variant == 'equivalent':
        changes.reverse()
        for change in changes:
            change['change']['actions'].reverse()
        changes.append({'address': 'data.local_file.read_only', 'change': {'actions': ['read']}})
    elif variant == 'extra-change':
        changes.append({'address': 'local_file.extra', 'change': {'actions': ['create']}})
    elif variant == 'missing-instance':
        changes.pop()
    elif variant == 'one-sided':
        changes[0]['change']['actions'] = ['create']
    (tmp_path / 'fanout-plan.json').write_text(json.dumps({'resource_changes': changes}))
    assert run_python(monkeypatch, tmp_path, '064', 1) == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-original-id', 'wrong-file', 'extra-entry', 'wrong-action'])
def test_071_saved_recovery_property(monkeypatch, tmp_path, variant):
    (tmp_path / 'north.txt').write_text('north-71')
    changes = [dict(resource('north.txt', 'local_file.north'), change={'actions': ['no-op'], 'before': {'filename': 'north.txt', 'id': 'original'}}), dict(resource('south.txt', 'local_file.south'), change={'actions': ['create'], 'after': {'filename': 'south.txt'}})]
    if variant == 'equivalent':
        changes[0]['address'] = 'local_file.restored[0]'
        changes[1]['address'] = 'module.new.local_file.route'
        changes.reverse()
    elif variant == 'wrong-original-id':
        changes[0]['change']['before']['id'] = 'recreated'
    elif variant == 'wrong-file':
        changes[1]['change']['after']['filename'] = 'other.txt'
    elif variant == 'extra-entry':
        changes.append({'change': {'actions': ['no-op']}})
    elif variant == 'wrong-action':
        changes[0]['change']['actions'] = ['delete', 'create']
    (tmp_path / 'recovery-plan.json').write_text(json.dumps({'resource_changes': changes}))
    assert run_python(monkeypatch, tmp_path, '071', 3) == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('source,refs,expected', [
    ('output "route" { value = trimspace(local_file.contract.content) }', ['local_file.contract.content', 'local_file.contract'], 0),
    ('locals { forwarded = local_file.contract.content }\noutput "route" { value = trimspace(local.forwarded) }', ['local.forwarded'], 0),
    ('locals { a = local_file.contract.content\n b = local.a }\noutput "route" { value = chomp((local.b)) }', ['local.b'], 0),
    ('output "route" { value = "north-98" }', [], 1),
    ('locals { forwarded = "north-98" }\noutput "route" { value = local.forwarded }', ['local.forwarded'], 1),
    ('output "route" { value = true ? "north-98" : local_file.contract.content }', ['local_file.contract.content'], 1),
    ('locals { fake = "local_file.contract.content" }\noutput "route" { value = local.fake }', ['local.fake'], 1),
    ('locals { a = local.b\n b = local.a }\noutput "route" { value = local.a }', ['local.a'], 1),
    ('# locals { a = local_file.contract.content }\nlocals { a = "north-98" }\noutput "route" { value = local.a }', ['local.a'], 1),
    ('locals { a = <<EOF\nlocal_file.contract.content\nEOF\n}\noutput "route" { value = local.a }', ['local.a'], 1),
])
def test_098_source_forwarding_not_constant_or_decoy(monkeypatch, tmp_path, source, refs, expected):
    directory = tmp_path / 'modules' / 'station'
    directory.mkdir(parents=True)
    (directory / 'main.tf').write_text(source)
    (tmp_path / 'managed-route.txt').write_text('north-98')
    plan = state(('module.station', resource('managed-route.txt', 'module.station.local_file.contract')), section='planned_values')
    plan['configuration'] = {'root_module': {'module_calls': {'station': {'source': './modules/station', 'module': {'outputs': {'route': {'expression': {'references': refs}}}}}}}}
    assert run_python(monkeypatch, tmp_path, '098', 1, document=plan, tag='DQ_REFERENCE') == expected


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'allowed-destroy', 'wrong-protection', 'unrelated-error'])
def test_029_protection_belongs_to_managed_notice(monkeypatch, tmp_path, variant):
    (tmp_path / 'notice.txt').write_text('north-ready')
    address = 'local_file.notice' if variant == 'reference' else 'module.current.local_file.notice["north"]'
    document = state((None, resource('notice.txt', address)))
    seen = []

    def plan(argv):
        seen.append(argv)
        protected = 'local_file.unrelated' if variant == 'wrong-protection' else address
        text = f'Resource instance {protected} has prevent_destroy set, but the plan\ncalls for it to be destroyed.'
        if variant == 'unrelated-error':
            text = 'Provider could not start'
        return SimpleNamespace(returncode=0 if variant == 'allowed-destroy' else 1, stdout=text, stderr='')

    assert run_python(monkeypatch, tmp_path, '029', 2, document=document, plans=plan) == (0 if variant in ('reference', 'equivalent') else 1)
    assert seen and '-target=' + address in seen[0]


def run_shell(tmp_path, quest, index, *, response, stage=0, status=0, deployment=None, running='north-98'):
    """Real aggregate objective shell, jq and isolated Python; only CLI I/O is fake."""
    import os

    bin_path = tmp_path / 'bin'
    bin_path.mkdir(exist_ok=True)
    (tmp_path / 'cli-response.json').write_text(json.dumps(response))
    if deployment is not None:
        (tmp_path / 'deployment.json').write_text(json.dumps(deployment))
    for tool in ('tofu', 'kubectl'):
        executable = bin_path / tool
        executable.write_text('#!/bin/sh\n'
                              'case "$1" in\n'
                              'get) cat deployment.json ;;\n'
                              'exec) case " $* " in *" -c worker "*) printf "%s\\n" "$DQ_TEST_RUNNING" ;; *) exit 2 ;; esac ;;\n'
                              '*) cat cli-response.json ;;\n'
                              'esac\nexit "$DQ_TEST_STATUS"\n')
        executable.chmod(0o755)
    return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + objective(quest, index, stage)], cwd=tmp_path, env={**os.environ, 'PATH': str(bin_path) + ':' + os.environ['PATH'], 'DQ_TEST_RUNNING': running, 'DQ_TEST_STATUS': str(status)}, text=True, capture_output=True)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-release', 'wrong-checksum', 'wrong-depot', 'cli-failed'])
def test_047_saved_release_contract_not_source_directory(tmp_path, variant):
    import hashlib

    (tmp_path / 'north.txt').write_text('north-47\n')
    checksum = hashlib.sha256((tmp_path / 'north.txt').read_bytes()).hexdigest()
    contracts = {'station': {'release': 2, 'checksum': checksum}, 'depot': {'release': 1}}
    saved = copy.deepcopy(contracts)
    if variant == 'wrong-release':
        saved['station']['release'] = 1
    elif variant == 'wrong-checksum':
        saved['station']['checksum'] = '0' * 64
    elif variant == 'wrong-depot':
        saved['depot']['release'] = 2
    directory = './modules/v2' if variant == 'reference' else './renamed-module-directory'
    plan = {'planned_values': {'outputs': {'contracts': {'value': saved}}}, 'configuration': {'root_module': {'module_calls': {'station': {'source': directory}}}}}
    (tmp_path / 'upgrade-plan.json').write_text(json.dumps(plan))
    result = run_shell(tmp_path, '047', 3, response=contracts, status=1 if variant == 'cli-failed' else 0)
    assert result.returncode == (0 if variant in ('reference', 'equivalent') else 1), result.stdout + result.stderr


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'embedded', 'wrong-key', 'wrong-live-value', 'no-worker', 'two-route-entries', 'wrong-replicas'])
def test_098_named_running_worker_contract(tmp_path, variant):
    route = {'name': 'ROUTE', 'valueFrom': {'configMapKeyRef': {'name': 'route', 'key': 'route'}}}
    worker = {'name': 'worker', 'env': [route]}
    board = {'spec': {'replicas': 1, 'template': {'spec': {'containers': [worker]}}}}
    if variant == 'equivalent':
        route['valueFrom']['configMapKeyRef']['optional'] = False
        worker['env'].append({'name': 'UNRELATED', 'value': 'kept'})
        board['spec']['template']['spec']['containers'].insert(0, {'name': 'sidecar', 'env': []})
    elif variant == 'embedded':
        route['value'] = 'north-98'
    elif variant == 'wrong-key':
        route['valueFrom']['configMapKeyRef']['key'] = 'other'
    elif variant == 'no-worker':
        worker['name'] = 'unrelated'
    elif variant == 'two-route-entries':
        worker['env'].append(copy.deepcopy(route))
    elif variant == 'wrong-replicas':
        board['spec']['replicas'] = 2
    result = run_shell(tmp_path, '098', 4, response={}, deployment=board, running='retired-98' if variant == 'wrong-live-value' else 'north-98')
    assert result.returncode == (0 if variant in ('reference', 'equivalent') else 1), result.stdout + result.stderr


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-module', 'missing-original'])
def test_064_original_inventory_is_order_independent(monkeypatch, tmp_path, variant):
    original = ['module.stations["depot"].local_file.route', 'module.stations["junction"].local_file.route']
    (tmp_path / 'original-addresses').write_text('\n'.join(original))
    records = [(None, resource(name + '.txt', address)) for address, name in zip(original, ('depot', 'junction'))]
    if variant == 'equivalent':
        records.reverse()
        records.append((None, resource('unrelated.txt', 'local_file.extra')))
    elif variant == 'wrong-module':
        records[0][1]['address'] = 'module.other.local_file.route'
    elif variant == 'missing-original':
        records.pop()
    assert run_python(monkeypatch, tmp_path, '064', 2, document=state(*records)) == (0 if variant in ('reference', 'equivalent') else 1)


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong-output', 'wrong-artifact', 'wrong-configmap', 'cli-failed'])
def test_098_published_contract_checks_only_required_route(tmp_path, variant):
    import os

    (tmp_path / 'managed-route.txt').write_text('north-98')
    module = tmp_path / 'modules' / 'station'
    module.mkdir(parents=True)
    (module / 'main.tf').write_text('output "route" { value = trimspace(local_file.contract.content) }')
    plan = state(('module.station', resource('managed-route.txt', 'module.station.local_file.contract')), section='planned_values')
    plan['configuration'] = {'root_module': {'module_calls': {'station': {'source': './modules/station', 'module': {'outputs': {'route': {'expression': {'references': ['local_file.contract.content']}}}}}}}}
    contract = {'route': 'north-98'}
    artifact = dict(contract)
    configmap = {'data': dict(contract)}
    if variant == 'equivalent':
        contract['unrelated'] = 'kept'
        artifact['unrelated'] = 42
        configmap['data']['unrelated'] = 'kept'
    elif variant == 'wrong-output':
        contract['route'] = 'retired-98'
    elif variant == 'wrong-artifact':
        artifact['route'] = 'retired-98'
    elif variant == 'wrong-configmap':
        configmap['data']['route'] = 'retired-98'
    for filename, document in [('plan.json', plan), ('output.json', contract), ('contract.json', artifact), ('configmap.json', configmap)]:
        (tmp_path / filename).write_text(json.dumps(document))
    bin_path = tmp_path / 'bin'
    bin_path.mkdir()
    programs = {
        'tofu': 'case "$1" in output) cat output.json ;; show) cat plan.json ;; plan) : ;; *) exit 2 ;; esac\nexit "$DQ_TEST_STATUS"',
        'kubectl': 'case "$1" in get) cat configmap.json ;; exec) case " $* " in *" -c worker "*) printf "north-98\\n" ;; *) exit 2 ;; esac ;; *) exit 2 ;; esac',
        'curl': 'printf "north-98\\n"',
    }
    for name, code in programs.items():
        path = bin_path / name
        path.write_text('#!/bin/sh\n' + code + '\n')
        path.chmod(0o755)
    result = subprocess.run(['bash', '-c', 'set -euo pipefail\n' + objective('098', 1)], cwd=tmp_path, env={**os.environ, 'PATH': str(bin_path) + ':' + os.environ['PATH'], 'DQ_NAMESPACE': 'dq-synthetic', 'DQ_TEST_STATUS': '1' if variant == 'cli-failed' else '0'}, text=True, capture_output=True)
    assert result.returncode == (0 if variant in ('reference', 'equivalent') else 1), result.stdout + result.stderr


def test_081_running_release_probe_selects_worker(tmp_path):
    result = run_shell(tmp_path, '081', 1, stage=2, response={}, running='release-81')
    assert result.returncode == 0, result.stdout + result.stderr
    result = run_shell(tmp_path, '081', 1, stage=2, response={}, running='retired')
    assert result.returncode == 1


@pytest.mark.parametrize('expression,address,expected', [
    ('trimspace(local_file.contract[0].content)', 'local_file.contract[0]', 0),
    ('trimspace(local_file.contract["north"].content)', 'local_file.contract["north"]', 0),
    ('trimspace(local_file.contract["0"].content)', 'local_file.contract["0"]', 0),
    ('trimspace(local_file.contract[0].content)', 'local_file.contract["0"]', 1),
    ('trimspace(local_file.contract[0].content)', 'local_file.contract[1]', 1),
    ('trimspace(local_file.contract["north"].content)', 'local_file.contract["south"]', 1),
])
def test_098_literal_instance_indices_preserve_producer_identity(monkeypatch, tmp_path, expression, address, expected):
    directory = tmp_path / 'modules' / 'station'
    directory.mkdir(parents=True)
    (directory / 'main.tf').write_text('output "route" { value = ' + expression + ' }')
    (tmp_path / 'managed-route.txt').write_text('north-98')
    plan = state(('module.station', resource('managed-route.txt', 'module.station.' + address)), section='planned_values')
    reference = expression[len('trimspace('):-1]
    plan['configuration'] = {'root_module': {'module_calls': {'station': {'source': './modules/station', 'module': {'outputs': {'route': {'expression': {'references': [reference]}}}}}}}}
    assert run_python(monkeypatch, tmp_path, '098', 1, document=plan, tag='DQ_REFERENCE') == expected
