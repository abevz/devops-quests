"""Native startup contract for all quests, including later-stage setup.

A retained condition still runs through Engine.poll and blocks Check & finish.
Exceptions name genuine completion goals that are coincidentally true initially.
"""
import asyncio
import copy
import hashlib
import json
import os
import threading

import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.runtime import Runtime
from devops_quests.store import Store


# Zero-based stage/objective. Each exception must be explained in the PR audit.
INITIAL_GOAL_EXCEPTIONS = {
    (11, 0, 0): "Rollout reports completion during startup despite the supplied broken clock command; availability remains a repair goal, not a preservation constraint.",
    (14, 0, 1): "Rollout can report completion while the supplied worker still has the wrong route; restoring the service remains a genuine repair goal.",
    (34, 0, 3): "The initial four-CPU request can fit this host, so rollout may already finish; restoring availability under the required budget remains a genuine goal.",
    (34, 0, 4): "The oversized initial workload can run on this host and already serve HTTP; the required budget is still unmet and final HTTP remains a repair postcondition.",
}


class ResourcePressure(RuntimeError):
    """Keep host/container pressure separate from a failed quest condition."""


def expected_startup_oom(number, resources, pods):
    """088 deliberately starts this exact broken workload, not a healthy baseline."""
    if number != 88:
        return False
    for container in resources['containers'].values():
        if container['oom_killed'] or any(
            line.startswith('oom_kill ') and int(line.split()[1]) > 0
            for line in container.get('memory_events', '').splitlines()
        ):
            return False
    found = False
    for pod in pods:
        for status in pod.get('status', {}).get('containerStatuses', []):
            for field in ('state', 'lastState'):
                if status.get(field, {}).get('terminated', {}).get('reason') != 'OOMKilled':
                    continue
                found = True
                workers = [c for c in pod['spec']['containers'] if c['name'] == status['name']]
                if pod['metadata'].get('labels', {}).get('app') != 'relay' or status['name'] != 'worker' or len(workers) != 1:
                    return False
                worker = workers[0]
                if worker.get('command') != ['sh', '-c', 'x=xxxxxxxx; while :; do x=$x$x; done'] or worker.get('resources', {}).get('limits', {}).get('memory') != '16Mi':
                    return False
    return found


def resource_observation(runtime, run):
    result = {'containers': {}, 'oom': False}
    for role, name in runtime.names(run).items():
        container = runtime.inspect(name)
        if not container:
            continue
        assert container.get('Config', {}).get('Labels', {}).get('devops-quests.installation') == runtime.installation
        state = container['State']
        item = {'oom_killed': bool(state.get('OOMKilled'))}
        if state.get('Running'):
            events = runtime.docker('exec', name, 'cat', '/sys/fs/cgroup/memory.events', check=False, timeout=10)
            item['events_rc'] = events.returncode
            item['memory_events'] = events.stdout
            result['oom'] |= any(line.split()[0] == 'oom_kill' and int(line.split()[1]) > 0 for line in events.stdout.splitlines())
        result['oom'] |= item['oom_killed']
        result['containers'][role] = item
    if 'kubernetes' in runtime.dependencies(run):
        pods = runtime.kube('-n', runtime.namespace(run), 'get', 'pods', '-o', 'json')
        statuses = [status for pod in json.loads(pods.stdout)['items'] for status in pod.get('status', {}).get('containerStatuses', [])]
        result['pod_terminations'] = [status.get(field, {}).get('terminated', {}) for status in statuses for field in ('state', 'lastState')]
        result['oom'] |= any(item.get('reason') == 'OOMKilled' for item in result['pod_terminations'])
    return result


@pytest.fixture(scope='module')
def initial_catalog():
    return Catalog()


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
@pytest.mark.parametrize('number', range(1, 131))
async def test_initial_objectives(number, initial_catalog, tmp_path):
    catalog = initial_catalog
    runtime = Runtime(ROOT / '.state/runtime')
    store = Store(tmp_path / 'synthetic/progress.db')
    token = store.login('admin', store.bootstrap().read_text().strip(), 'synthetic')
    user = store.session(token)['user_id']
    engine = Engine(store, catalog, runtime)
    evidence = ROOT / 'artifacts/initial-objectives'
    evidence.mkdir(parents=True, exist_ok=True)
    record = {'quest': number, 'installation': runtime.installation, 'stages': []}
    record['sources'] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for directory in (ROOT / f'quests/{number:03}', ROOT / f'solutions/{number:03}')
        for p in directory.rglob('*') if p.is_file()
    }
    try:
        run = await engine.start(user, number, 'free', minutes=120)
        for stage_index, stage in enumerate(catalog.quests[number]['stages']):
            initial = await engine.poll(run)
            assert initial['status'] == 'active' and initial['stage'] == stage_index, 'Setup already satisfied every condition'
            observed = {'stage': stage_index, 'goals': initial['goals'], 'keep': [g.get('keep', False) for g in stage['objectives']]}
            record['stages'].append(observed)
            observed['resources_after_probes'] = resource_observation(runtime, run)
            if observed['resources_after_probes']['oom']:
                pods = json.loads(runtime.kube('-n', runtime.namespace(run), 'get', 'pods', '-o', 'json').stdout)['items'] if number == 88 else []
                observed['expected_incident_oom'] = expected_startup_oom(number, observed['resources_after_probes'], pods)
                if observed['expected_incident_oom']:
                    record['expected_incident_oom'] = True
                    observed['expected_oom_pods'] = pods
                else:
                    raise ResourcePressure('Unexpected OOM observed in this owned bay; startup classification is not qualified')
            assert len(initial['goals']) == len(stage['objectives'])
            for index, (goal, passed) in enumerate(zip(stage['objectives'], initial['goals'], strict=True)):
                key = (number, stage_index, index)
                assert not passed or goal.get('keep', False) or key in INITIAL_GOAL_EXCEPTIONS, f'Initially complete goal without keep or justified exception: {key}'
            if stage_index + 1 < len(catalog.quests[number]['stages']):
                stop = threading.Event()
                errors = []

                def observe():
                    while not stop.wait(2.5):
                        try:
                            if number in {121, 123}:
                                runtime.game_controls(run)
                            else:
                                runtime.observe(run)
                        except Exception as error:
                            errors.append(str(error))

                observer = threading.Thread(target=observe, daemon=True) if number in {77, 116, 117, 121, 123} else None
                if observer:
                    observer.start()
                try:
                    reference = (ROOT / f'solutions/{number:03}/{stage_index}.sh').read_text()
                    await asyncio.to_thread(runtime.exec, run, reference, timeout=240)
                finally:
                    stop.set()
                    if observer:
                        observer.join(timeout=10)
                        assert not observer.is_alive() and not errors, errors
                advanced = await engine.poll(run, final=True)
                observed['reference_result'] = advanced.get('check_result')
                assert advanced['status'] == 'active' and advanced['stage'] == stage_index + 1, advanced.get('check_result')
                run = advanced
        record['result'] = 'PASS'
    except Exception as error:
        record['result'] = 'RESOURCE_PRESSURE' if isinstance(error, ResourcePressure) else 'FAIL'
        record['error'] = str(error)
        current = store.run(user=user)
        if current:
            try:
                record['resources_at_failure'] = resource_observation(runtime, current)
                if record['resources_at_failure']['oom'] and not record.get('expected_incident_oom', False):
                    record['result'] = 'RESOURCE_PRESSURE'
            except Exception as diagnostic_error:
                record['resource_observation_error'] = str(diagnostic_error)
        raise
    finally:
        try:
            await engine.stop(user)
        finally:
            (evidence / f'{number:03}.json').write_text(json.dumps(record, indent=2) + '\n')


def test_initial_goal_exception_coordinates_are_explained_and_are_not_keep():
    catalog = Catalog()
    for (number, stage, index), reason in INITIAL_GOAL_EXCEPTIONS.items():
        assert len(reason) >= 40
        assert not catalog.quests[number]['stages'][stage]['objectives'][index].get('keep', False)


@pytest.mark.parametrize('variant', ['expected', 'other_quest', 'host_oom', 'other_app', 'other_container', 'fixed_limit', 'fixed_command'])
def test_expected_startup_oom_is_narrow(variant):
    resources = {'containers': {'workstation': {'oom_killed': False, 'memory_events': 'oom_kill 0\n'}}}
    pods = [{'metadata': {'labels': {'app': 'relay'}}, 'spec': {'containers': [{'name': 'worker', 'command': ['sh', '-c', 'x=xxxxxxxx; while :; do x=$x$x; done'], 'resources': {'limits': {'memory': '16Mi'}}}]}, 'status': {'containerStatuses': [{'name': 'worker', 'lastState': {'terminated': {'reason': 'OOMKilled'}}}]}}]
    number = 88
    if variant == 'other_quest':
        number = 87
    elif variant == 'host_oom':
        resources['containers']['workstation']['memory_events'] = 'oom_kill 1\n'
    elif variant == 'other_app':
        extra = copy.deepcopy(pods[0])
        extra['metadata']['labels']['app'] = 'unrelated'
        pods.append(extra)
    elif variant == 'other_container':
        pods[0]['status']['containerStatuses'][0]['name'] = 'unrelated'
    elif variant == 'fixed_limit':
        pods[0]['spec']['containers'][0]['resources']['limits']['memory'] = '96Mi'
    elif variant == 'fixed_command':
        pods[0]['spec']['containers'][0]['command'] = ['sleep', '3600']
    assert expected_startup_oom(number, resources, pods) is (variant == 'expected')
