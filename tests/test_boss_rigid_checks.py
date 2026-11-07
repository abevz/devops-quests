"""Run the shipped Boss predicates against equivalent and incorrect observations."""

import copy
import json
import os
import subprocess
from functools import lru_cache
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
IMAGE = 'registry.invalid/parcel@sha256:' + 'a' * 64


@lru_cache(maxsize=None)
def quest(number):
    return yaml.safe_load((ROOT / f'quests/{number:03}/quest.yaml').read_text())


def goal(number, stage, index):
    return quest(number)['stages'][stage]['objectives'][index]['check']


def execute(monkeypatch, tmp_path, number, stage, index, documents):
    source = goal(number, stage, index).split("<<'DQ_BOSS'\n", 1)[1].split('\nDQ_BOSS', 1)[0]
    source = source.replace('/run/dq/facts/0/', str(tmp_path / 'facts') + '/')
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv('DQ_NAMESPACE', 'dq-synthetic')
    (tmp_path / 'facts').mkdir(exist_ok=True)
    (tmp_path / 'facts/private-release.json').write_text(json.dumps({'image': IMAGE}))
    (tmp_path / 'facts/ingress-target.json').write_text(json.dumps({'class': 'private'}))
    (tmp_path / 'facts/gateway-target.json').write_text(json.dumps({'namespace': 'gateway-private'}))
    unexpected = []
    calls = []

    def output(argv, **kwargs):
        calls.append(argv)
        key = None
        if argv[:2] == ['kubectl', 'get']:
            key = (argv[2], None if argv[3] == '-o' else argv[3])
        elif argv[:2] == ['kubectl', 'exec']:
            assert '-c' in argv and argv[argv.index('-c') + 1] == 'worker'
            key = ('exec', argv[3])
        elif argv[:3] == ['tofu', 'show', '-json']:
            key = ('state', None)
        elif argv[:2] == ['ansible-inventory', '--list']:
            key = ('inventory', None)
        elif argv[:3] == ['ansible', 'all', '--list-hosts']:
            return '  hosts (3):\n    app1\n    app2\n    app3\n'
        elif argv[:4] == ['git', '-C', 'repository', 'show']:
            return yaml.safe_dump(documents[('git', None)]).encode()
        if key not in documents:
            unexpected.append(argv)
            raise RuntimeError('Unconfigured fixture command')
        value = documents[key]
        if isinstance(value, bytes):
            return value
        text = json.dumps(value)
        return text if kwargs.get('text') else text.encode()

    monkeypatch.setattr(subprocess, 'check_output', output)
    monkeypatch.setattr(subprocess, 'check_call', lambda *a, **k: 0)
    try:
        exec(compile(source, 'shipped-boss-check', 'exec'), {'__name__': '__main__'})
        result = 0
    except SystemExit as error:
        result = error.code or 0
    assert not unexpected, unexpected
    return result, calls


def deployment():
    worker = {'name': 'worker', 'image': IMAGE, 'imagePullPolicy': 'Always',
              'env': [{'name': 'ROUTE_SECRET', 'valueFrom': {'secretKeyRef': {'name': 'route-secret', 'key': 'value'}}}],
              'ports': [{'name': 'http', 'containerPort': 8080}],
              'resources': {'requests': {'cpu': '100m'}, 'limits': {'cpu': '200m'}}}
    return {'kind': 'Deployment', 'metadata': {'name': 'board', 'uid': 'dep'},
            'spec': {'replicas': 2, 'strategy': {'type': 'RollingUpdate', 'rollingUpdate': {'maxSurge': 1, 'maxUnavailable': 0}},
                     'template': {'metadata': {'labels': {'app': 'board', 'part': 'api'}},
                                  'spec': {'containers': [worker], 'imagePullSecrets': [{'name': 'registry-pull'}]}}},
            'status': {'availableReplicas': 2, 'readyReplicas': 2}}


def private_documents():
    d = deployment()
    worker = copy.deepcopy(d['spec']['template']['spec']['containers'][0])
    rs = {'items': [{'metadata': {'uid': 'rs', 'ownerReferences': [{'kind': 'Deployment', 'uid': 'dep', 'controller': True}]}}]}
    pod = {'metadata': {'name': 'board-pod', 'uid': 'pod', 'labels': {'app': 'board'}, 'ownerReferences': [{'kind': 'ReplicaSet', 'uid': 'rs', 'controller': True}]},
           'spec': {'containers': [worker], 'imagePullSecrets': [{'name': 'registry-pull'}]},
           'status': {'phase': 'Running', 'containerStatuses': [{'name': 'worker', 'ready': True, 'state': {'running': {}}, 'imageID': 'containerd://sha256:' + 'a' * 64}]}}
    return {('deployment', 'board'): d, ('replicasets', None): rs, ('pods', None): {'items': [pod]}}


@pytest.mark.parametrize('number', [20, 30, 90])
@pytest.mark.parametrize('variant', ['reference', 'renamed-module', 'data-only', 'wrong-file', 'untracked'])
def test_managed_release_by_file(monkeypatch, tmp_path, number, variant):
    (tmp_path / 'release.txt').write_text('release')
    resource = {'address': 'local_file.release', 'mode': 'managed', 'type': 'local_file', 'values': {'filename': './release.txt'}}
    root = {'resources': [resource]}
    if variant == 'renamed-module':
        resource['address'] = 'module.delivery.local_file.artifact[0]'
        resource['values']['filename'] = str(tmp_path / 'release.txt')
        root = {'child_modules': [{'resources': [resource]}]}
    elif variant == 'data-only':
        resource['mode'] = 'data'
    elif variant == 'wrong-file':
        (tmp_path / 'other.txt').write_text('release')
        resource['values']['filename'] = 'other.txt'
    elif variant == 'untracked':
        root = {}
    result, _ = execute(monkeypatch, tmp_path, number, 0, 0, {('state', None): {'values': {'root_module': root}}})
    assert (result == 0) is (variant in {'reference', 'renamed-module'})


@pytest.mark.parametrize('variant', ['reference', 'string', 'list', 'percentage', 'large', 'unlimited', 'mixed', 'boolean'])
def test_one_host_serial_limit(monkeypatch, tmp_path, variant):
    value = {'reference': 1, 'string': '1', 'list': ['1', 1], 'percentage': '50%', 'large': 2, 'unlimited': 0, 'mixed': [1, 2], 'boolean': True}[variant]
    (tmp_path / 'rollout.yml').write_text(yaml.safe_dump([{'hosts': 'fleet', 'serial': value, 'tasks': []}]))
    inventory = {'all': {'children': ['fleet']}, 'fleet': {'hosts': ['app1', 'app2', 'app3']}}
    result, _ = execute(monkeypatch, tmp_path, 40, 0, 0, {('inventory', None): inventory})
    assert (result == 0) is (variant in {'reference', 'string', 'list', 'percentage'})


@pytest.mark.parametrize('variant', ['reference', 'percent', 'unavailable', 'surge', 'recreate', 'wrong-count', 'not-available'])
def test_effective_rolling_budget(monkeypatch, tmp_path, variant):
    d = deployment()
    if variant == 'percent':
        d['spec']['strategy']['rollingUpdate'] = {'maxSurge': '50%', 'maxUnavailable': '0%'}
    elif variant == 'unavailable':
        d['spec']['strategy']['rollingUpdate']['maxUnavailable'] = '50%'
    elif variant == 'surge':
        d['spec']['strategy']['rollingUpdate']['maxSurge'] = 2
    elif variant == 'recreate':
        d['spec']['strategy']['type'] = 'Recreate'
    elif variant == 'wrong-count':
        d['spec']['replicas'] = 3
    elif variant == 'not-available':
        d['status']['availableReplicas'] = 1
    result, _ = execute(monkeypatch, tmp_path, 40, 1, 0, {('deployment', 'board'): d})
    assert (result == 0) is (variant in {'reference', 'percent'})


@pytest.mark.parametrize('variant', ['reference', 'named-extra', 'broad-selector', 'wrong-selector', 'wrong-port', 'wrong-target', 'wrong-protocol'])
def test_service_fields_not_position(monkeypatch, tmp_path, variant):
    d = deployment()
    s = {'spec': {'selector': {'app': 'board'}, 'ports': [{'port': 8080, 'targetPort': 8080}]}}
    if variant == 'named-extra':
        s['spec']['selector']['part'] = 'api'
        s['spec']['ports'].insert(0, {'name': 'metrics', 'port': 9090, 'targetPort': 9090})
        s['spec']['ports'][1]['targetPort'] = 'http'
    elif variant == 'wrong-selector':
        s['spec']['selector']['app'] = 'other'
    elif variant == 'broad-selector':
        s['spec']['selector'] = {'part': 'api'}
    elif variant == 'wrong-port':
        s['spec']['ports'][0]['port'] = 9090
    elif variant == 'wrong-target':
        s['spec']['ports'][0]['targetPort'] = 'absent'
    elif variant == 'wrong-protocol':
        s['spec']['ports'][0]['protocol'] = 'UDP'
    result, _ = execute(monkeypatch, tmp_path, 40, 1, 1, {('deployment', 'board'): d, ('service', 'board'): s})
    assert (result == 0) is (variant in {'reference', 'named-extra'})


@pytest.mark.parametrize('number,stage,index', [(70, 0, 1), (70, 1, 2), (100, 1, 3)])
@pytest.mark.parametrize('variant', ['reference', 'sidecar-extra-env', 'literal', 'wrong-secret', 'wrong-key', 'duplicate'])
def test_nonembedded_named_secret(monkeypatch, tmp_path, number, stage, index, variant):
    docs = private_documents()
    d = docs[('deployment', 'board')]
    w = d['spec']['template']['spec']['containers'][0]
    if variant == 'sidecar-extra-env':
        w['env'].insert(0, {'name': 'UNRELATED', 'value': 'allowed'})
        w['env'][1]['valueFrom']['secretKeyRef']['optional'] = False
        d['spec']['template']['spec']['containers'].insert(0, {'name': 'observer'})
    elif variant == 'literal':
        w['env'][0] = {'name': 'ROUTE_SECRET', 'value': 'north-secret'}
    elif variant == 'wrong-secret':
        w['env'][0]['valueFrom']['secretKeyRef']['name'] = 'other'
    elif variant == 'wrong-key':
        w['env'][0]['valueFrom']['secretKeyRef']['key'] = 'other'
    elif variant == 'duplicate':
        w['env'].append(copy.deepcopy(w['env'][0]))
    result, _ = execute(monkeypatch, tmp_path, number, stage, index, docs)
    assert (result == 0) is (variant in {'reference', 'sidecar-extra-env'})


@pytest.mark.parametrize('number,index', [(80, 5), (100, 6)])
@pytest.mark.parametrize('variant', ['reference', 'observer-first', 'decoy', 'foreign', 'terminating', 'not-running', 'substring'])
def test_exact_current_worker_digest(monkeypatch, tmp_path, number, index, variant):
    docs = private_documents()
    pod = docs[('pods', None)]['items'][0]
    status = pod['status']['containerStatuses'][0]
    if variant in {'observer-first', 'decoy'}:
        pod['spec']['containers'].insert(0, {'name': 'observer', 'image': IMAGE})
        pod['status']['containerStatuses'].insert(0, dict(status, name='observer'))
        if variant == 'decoy':
            status['imageID'] = 'containerd://sha256:' + 'b' * 64
    elif variant == 'foreign':
        pod['metadata']['ownerReferences'][0]['uid'] = 'unrelated'
    elif variant == 'terminating':
        pod['metadata']['deletionTimestamp'] = 'now'
    elif variant == 'not-running':
        status['state'] = {'waiting': {}}
    elif variant == 'substring':
        status['imageID'] += 'extra'
    result, _ = execute(monkeypatch, tmp_path, number, 1, index, docs)
    assert (result == 0) is (variant in {'reference', 'observer-first'})


@pytest.mark.parametrize('variant', ['reference', 'sa-inherited', 'policy', 'extra-secret', 'no-pod'])
def test_effective_only_existing_pull_auth(monkeypatch, tmp_path, variant):
    docs = private_documents()
    d = docs[('deployment', 'board')]
    if variant == 'sa-inherited':
        d['spec']['template']['spec'].pop('imagePullSecrets')
    elif variant == 'policy':
        d['spec']['template']['spec']['containers'][0]['imagePullPolicy'] = 'Never'
    elif variant == 'extra-secret':
        docs[('pods', None)]['items'][0]['spec']['imagePullSecrets'].append({'name': 'other'})
    elif variant == 'no-pod':
        docs[('pods', None)]['items'] = []
    result, _ = execute(monkeypatch, tmp_path, 80, 0, 1, docs)
    assert (result == 0) is (variant in {'reference', 'sa-inherited'})


@pytest.mark.parametrize('number,index', [(80, 2), (100, 1)])
@pytest.mark.parametrize('variant', ['reference', 'observer-env-sa', 'default-sa', 'wrong-worker', 'wrong-auth', 'literal-secret', 'decoy-kind'])
def test_published_named_workload(monkeypatch, tmp_path, number, index, variant):
    d = deployment()
    w = d['spec']['template']['spec']['containers'][0]
    if variant == 'observer-env-sa':
        d['spec']['template']['spec']['containers'].insert(0, {'name': 'observer', 'image': 'irrelevant'})
        w['env'].insert(0, {'name': 'UNRELATED', 'value': 'allowed'})
        d['spec']['template']['spec'].pop('imagePullSecrets')
    elif variant == 'wrong-worker':
        w['image'] = 'wrong'
    elif variant == 'wrong-auth':
        d['spec']['template']['spec']['imagePullSecrets'].append({'name': 'other'})
    elif variant == 'literal-secret':
        w['env'][0] = {'name': 'ROUTE_SECRET', 'value': 'north-secret'}
    elif variant == 'decoy-kind':
        d['kind'] = 'StatefulSet'
    elif variant == 'default-sa':
        d['spec']['template']['spec'].pop('imagePullSecrets')
        d['spec']['template']['spec']['serviceAccountName'] = None
    docs = {('git', None): d, ('serviceaccount', 'default'): {'imagePullSecrets': [{'name': 'registry-pull'}]}}
    result, _ = execute(monkeypatch, tmp_path, number, 1, index, docs)
    wrong = {'wrong-worker', 'decoy-kind'} | ({'wrong-auth'} if number == 80 else {'literal-secret'})
    assert (result == 0) is (variant not in wrong)


@pytest.mark.parametrize('variant', ['reference', 'duplicate', 'other', 'extra', 'policy'])
def test_only_private_dns_resolver(monkeypatch, tmp_path, variant):
    names = ['10.0.0.53']
    if variant == 'duplicate':
        names *= 2
    elif variant == 'other':
        names = ['10.0.0.54']
    elif variant == 'extra':
        names.append('10.0.0.54')
    d = deployment()
    spec = d['spec']['template']['spec']
    spec.update(dnsPolicy='ClusterFirst' if variant == 'policy' else 'None', dnsConfig={'nameservers': names})
    docs = {('deployment', 'client'): d, ('service', 'station-dns'): {'spec': {'clusterIP': '10.0.0.53'}}}
    for stage in (0, 1):
        result, _ = execute(monkeypatch, tmp_path, 110, stage, 0, docs)
        assert (result == 0) is (variant in {'reference', 'duplicate'})


@pytest.mark.parametrize('variant', ['reference', 'named-reordered-exact', 'alternate-service-port', 'wrong-host', 'wrong-backend', 'wrong-port', 'wrong-class', 'shadow'])
def test_matching_ingress_route(monkeypatch, tmp_path, variant):
    path = {'path': '/', 'pathType': 'Prefix', 'backend': {'service': {'name': 'board', 'port': {'number': 8080}}}}
    rule = {'host': 'station.internal', 'http': {'paths': [path]}}
    ingress = {'spec': {'ingressClassName': 'private', 'rules': [rule]}}
    if variant == 'named-reordered-exact':
        path.update(pathType='Exact')
        path['backend']['service']['port'] = {'name': 'http'}
        ingress['spec']['rules'].insert(0, {'host': 'other', 'http': {'paths': []}})
    elif variant == 'wrong-host':
        rule['host'] = 'other'
    elif variant == 'wrong-backend':
        path['backend']['service']['name'] = 'other'
    elif variant == 'wrong-port':
        path['backend']['service']['port'] = {'name': 'absent'}
    elif variant == 'wrong-class':
        ingress['spec']['ingressClassName'] = 'other'
    elif variant == 'shadow':
        shadow = copy.deepcopy(path)
        shadow['pathType'] = 'Exact'
        shadow['backend']['service']['name'] = 'other'
        rule['http']['paths'].append(shadow)
    docs = {('ingress', 'board'): ingress, ('service', 'board'): {'spec': {'ports': [{'name': 'http', 'port': 8080}]}}}
    if variant == 'alternate-service-port':
        path['backend']['service']['port'] = {'number': 80}
        docs[('service', 'board')]['spec']['ports'].append({'name': 'alternate', 'port': 80, 'targetPort': 8080})
    result, _ = execute(monkeypatch, tmp_path, 110, 1, 2, docs)
    assert (result == 0) is (variant in {'reference', 'named-reordered-exact', 'alternate-service-port'})


@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'zero', 'unbounded', 'excess', 'too-large-request', 'not-ready', 'observer-decoy'])
def test_cpu_budget_property(monkeypatch, tmp_path, variant):
    d = deployment()
    w = d['spec']['template']['spec']['containers'][0]
    if variant == 'equivalent':
        w['resources'] = {'requests': {'cpu': '50e-3', 'memory': '8Mi'}, 'limits': {'cpu': '2e-1', 'memory': '32Mi'}}
        d['spec']['template']['spec']['containers'].insert(0, {'name': 'observer'})
    elif variant == 'zero':
        w['resources']['requests']['cpu'] = '0'
    elif variant == 'unbounded':
        w['resources']['limits']['cpu'] = '0'
    elif variant == 'excess':
        w['resources']['limits']['cpu'] = '201m'
    elif variant == 'too-large-request':
        w['resources']['requests']['cpu'] = '300m'
    elif variant == 'not-ready':
        d['status']['readyReplicas'] = 1
    elif variant == 'observer-decoy':
        d['spec']['template']['spec']['containers'].insert(0, copy.deepcopy(w) | {'name': 'observer'})
        w['resources']['limits']['cpu'] = '300m'
    for stage in (0, 1):
        result, _ = execute(monkeypatch, tmp_path, 130, stage, 0, {('deployment', 'board'): d})
        assert (result == 0) is (variant in {'reference', 'equivalent'})


def hpa():
    return {'spec': {'scaleTargetRef': {'apiVersion': 'apps/v1', 'kind': 'Deployment', 'name': 'board'}, 'minReplicas': 1, 'maxReplicas': 2, 'metrics': [{'type': 'Resource', 'resource': {'name': 'cpu', 'target': {'type': 'Utilization', 'averageUtilization': 50}}}]},
            'status': {'currentReplicas': 2, 'desiredReplicas': 2, 'currentMetrics': [{'type': 'Resource', 'resource': {'name': 'cpu', 'current': {'averageUtilization': 75}}}]}}


@pytest.mark.parametrize('variant', ['reference', 'reordered', 'wrong-target', 'wrong-workload', 'wrong-kind', 'decoy-pressure', 'wrong-min', 'wrong-max', 'wrong-current', 'wrong-desired'])
def test_supplied_hpa_metric_by_name(monkeypatch, tmp_path, variant):
    d = hpa()
    if variant in {'reordered', 'decoy-pressure'}:
        d['spec']['metrics'].insert(0, {'type': 'Resource', 'resource': {'name': 'memory', 'target': {'type': 'Utilization', 'averageUtilization': 90}}})
        d['status']['currentMetrics'].insert(0, {'type': 'Resource', 'resource': {'name': 'memory', 'current': {'averageUtilization': 99}}})
        if variant == 'decoy-pressure':
            d['status']['currentMetrics'][1]['resource']['current']['averageUtilization'] = 10
    elif variant == 'wrong-target':
        d['spec']['metrics'][0]['resource']['target']['averageUtilization'] = 60
    elif variant == 'wrong-workload':
        d['spec']['scaleTargetRef']['name'] = 'other'
    elif variant == 'wrong-kind':
        d['spec']['scaleTargetRef']['kind'] = 'StatefulSet'
    elif variant == 'wrong-min':
        d['spec']['minReplicas'] = 2
    elif variant == 'wrong-max':
        d['spec']['maxReplicas'] = 3
    elif variant == 'wrong-current':
        d['status']['currentReplicas'] = 1
    elif variant == 'wrong-desired':
        d['status']['desiredReplicas'] = 1
    for stage in (0, 1):
        result, _ = execute(monkeypatch, tmp_path, 130, stage, 1, {('hpa', 'board'): d})
        assert (result == 0) is (variant in {'reference', 'reordered'})


@pytest.mark.parametrize('variant', ['reference', 'alternate-port', 'unrelated-rule', 'wrong-service', 'unknown-port', 'unresolved', 'foreign-namespace'])
def test_route_backend_resolves_app_service(monkeypatch, tmp_path, variant):
    backend = {'name': 'board', 'port': 8080}
    d = {'spec': {'rules': [{'backendRefs': [backend]}]}, 'status': {'parents': [{'conditions': [{'type': 'ResolvedRefs', 'status': 'True'}]}]}}
    if variant == 'alternate-port':
        backend['port'] = 80
    elif variant == 'unrelated-rule':
        d['spec']['rules'].insert(0, {'matches': [{'path': {'type': 'PathPrefix', 'value': '/unrelated'}}], 'backendRefs': [{'name': 'other', 'port': 9090}]})
    elif variant == 'wrong-service':
        backend['name'] = 'other'
    elif variant == 'unknown-port':
        backend['port'] = 9999
    elif variant == 'unresolved':
        d['status']['parents'][0]['conditions'][0]['status'] = 'False'
    elif variant == 'foreign-namespace':
        backend['namespace'] = 'other'
    docs = {('httproute', 'board'): d, ('service', 'board'): {'spec': {'ports': [{'port': 80}, {'port': 8080}]}}}
    result, _ = execute(monkeypatch, tmp_path, 130, 1, 3, docs)
    assert (result == 0) is (variant in {'reference', 'alternate-port', 'unrelated-rule'})


def egress_policy():
    return {'metadata': {'name': 'client-egress'}, 'spec': {'podSelector': {'matchLabels': {'app': 'client'}}, 'policyTypes': ['Egress'], 'egress': [
        {'to': [{'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'kube-system'}}, 'podSelector': {'matchLabels': {'k8s-app': 'kube-dns'}}}], 'ports': [{'port': 53, 'protocol': 'UDP'}, {'port': 53, 'protocol': 'TCP'}]},
        {'to': [{'podSelector': {'matchLabels': {'app': 'shelf'}}}], 'ports': [{'port': 8080}]}]}}


@pytest.mark.parametrize('variant', ['reference', 'named-redundant', 'safe-absent-label', 'contradictory-peer', 'broad-selector', 'unbounded-port', 'extra-grant', 'split-or', 'wrong-selector', 'other-policy', 'wrong-named', 'missing-dns'])
def test_only_egress_flows(monkeypatch, tmp_path, variant):
    policy = egress_policy()
    spec = policy['spec']
    if variant == 'named-redundant':
        spec['policyTypes'].append('Ingress')
        spec['podSelector']['matchExpressions'] = [{'key': 'app', 'operator': 'Exists'}]
        spec['egress'][1]['to'][0]['podSelector'] = {'matchExpressions': [{'key': 'app', 'operator': 'In', 'values': ['shelf', 'shelf']}]}
        spec['egress'][1]['ports'][0]['port'] = 'http'
    elif variant == 'extra-grant':
        spec['egress'][1]['ports'].append({'port': 9090})
    elif variant == 'split-or':
        peer = spec['egress'][0]['to'][0]
        spec['egress'][0]['to'] = [{'namespaceSelector': peer['namespaceSelector']}, {'podSelector': peer['podSelector']}]
    elif variant == 'wrong-selector':
        spec['podSelector']['matchLabels']['app'] = 'other'
    elif variant == 'broad-selector':
        spec['podSelector'] = {}
    elif variant == 'wrong-named':
        spec['egress'][1]['ports'][0]['port'] = 'absent'
    elif variant == 'missing-dns':
        spec['egress'][0]['ports'].pop()
    elif variant == 'safe-absent-label':
        spec['egress'][1]['to'][0]['podSelector']['matchExpressions'] = [{'key': 'unrelated', 'operator': 'DoesNotExist'}]
    elif variant == 'contradictory-peer':
        spec['egress'][1]['to'][0]['podSelector']['matchExpressions'] = [{'key': 'unrelated', 'operator': 'DoesNotExist'}, {'key': 'unrelated', 'operator': 'Exists'}]
    policies = [policy]
    if variant == 'other-policy':
        policies.append({'metadata': {'name': 'broad'}, 'spec': {'podSelector': {}, 'policyTypes': ['Egress'], 'egress': [{}]}})
    docs = {('networkpolicies', None): {'items': policies}, ('pods', None): {'items': [{'metadata': {'labels': {'app': 'client'}}}]},
            ('pod', 'shelf-0'): {'spec': {'containers': [{'ports': [{'name': 'http', 'containerPort': 8080}]}]}}}
    if variant == 'unbounded-port':
        spec['egress'][1]['ports'] = [{'protocol': 'TCP'}]
        docs[('pod', 'shelf-0')]['spec']['containers'][0]['ports'][0].pop('name')
    result, _ = execute(monkeypatch, tmp_path, 120, 0, 2, docs)
    assert (result == 0) is (variant in {'reference', 'named-redundant', 'safe-absent-label'})


@pytest.mark.parametrize('variant', ['reference', 'extra-selector', 'broad-selector', 'clusterip', 'wrong-selector'])
def test_storage_service_property(monkeypatch, tmp_path, variant):
    service = {'spec': {'clusterIP': 'None', 'selector': {'app': 'shelf'}}}
    if variant == 'extra-selector':
        service['spec']['selector']['part'] = 'data'
    elif variant == 'clusterip':
        service['spec']['clusterIP'] = '10.0.0.1'
    elif variant == 'wrong-selector':
        service['spec']['selector']['app'] = 'other'
    elif variant == 'broad-selector':
        service['spec']['selector'] = {'part': 'data'}
    docs = {('service', 'shelf'): service, ('pod', 'shelf-0'): {'metadata': {'labels': {'app': 'shelf', 'part': 'data'}}}}
    result, _ = execute(monkeypatch, tmp_path, 120, 0, 1, docs)
    assert (result == 0) is (variant in {'reference', 'extra-selector'})


@pytest.mark.parametrize('variant', ['reference', 'redundant-named', 'safe-absent-label', 'contradictory-peer', 'broad-selector', 'unbounded-port', 'extra-port', 'split-or', 'wrong-namespace', 'wrong-pod', 'wrong-selector'])
def test_only_gateway_ingress(monkeypatch, tmp_path, variant):
    peer = {'namespaceSelector': {'matchLabels': {'kubernetes.io/metadata.name': 'gateway-private'}}, 'podSelector': {'matchLabels': {'app': 'gateway'}}}
    spec = {'podSelector': {'matchLabels': {'app': 'board'}}, 'policyTypes': ['Ingress'], 'ingress': [{'from': [peer], 'ports': [{'port': 8080}]}]}
    if variant == 'redundant-named':
        peer['podSelector']['matchExpressions'] = [{'key': 'app', 'operator': 'Exists'}]
        spec['policyTypes'].append('Egress')
        spec['ingress'][0]['ports'] = [{'port': 'http'}]
    elif variant == 'extra-port':
        spec['ingress'][0]['ports'].append({'port': 9090})
    elif variant == 'split-or':
        spec['ingress'][0]['from'] = [{'namespaceSelector': peer['namespaceSelector']}, {'podSelector': peer['podSelector']}]
    elif variant == 'wrong-namespace':
        peer['namespaceSelector']['matchLabels']['kubernetes.io/metadata.name'] = 'other'
    elif variant == 'wrong-pod':
        peer['podSelector']['matchLabels']['app'] = 'other'
    elif variant == 'wrong-selector':
        spec['podSelector']['matchLabels']['app'] = 'other'
    elif variant == 'broad-selector':
        spec['podSelector'] = {}
    elif variant == 'safe-absent-label':
        peer['podSelector']['matchExpressions'] = [{'key': 'unrelated', 'operator': 'DoesNotExist'}]
    elif variant == 'contradictory-peer':
        peer['podSelector']['matchExpressions'] = [{'key': 'unrelated', 'operator': 'DoesNotExist'}, {'key': 'unrelated', 'operator': 'Exists'}]
    docs = {('networkpolicy', 'board-ingress'): {'spec': spec}, ('deployment', 'board'): deployment()}
    if variant == 'unbounded-port':
        spec['ingress'][0]['ports'] = [{'protocol': 'TCP'}]
        docs[('deployment', 'board')]['spec']['template']['spec']['containers'][0]['ports'][0].pop('name')
    result, _ = execute(monkeypatch, tmp_path, 130, 1, 4, docs)
    assert (result == 0) is (variant in {'reference', 'redundant-named', 'safe-absent-label'})


@pytest.mark.parametrize('variant', ['reference', 'observer-first', 'wrong-image', 'wrong-policy'])
def test_live_private_image_policy(monkeypatch, tmp_path, variant):
    d = deployment()
    w = d['spec']['template']['spec']['containers'][0]
    if variant == 'observer-first':
        d['spec']['template']['spec']['containers'].insert(0, {'name': 'observer', 'image': 'irrelevant'})
    elif variant == 'wrong-image':
        w['image'] = 'other'
    elif variant == 'wrong-policy':
        w['imagePullPolicy'] = 'Never'
    result, _ = execute(monkeypatch, tmp_path, 80, 1, 3, {('deployment', 'board'): d})
    assert (result == 0) is (variant in {'reference', 'observer-first'})


@pytest.mark.parametrize('variant', ['reference', 'extra-unrelated-pod', 'wrong-worker-response', 'foreign-only', 'empty'])
def test_every_running_application_pod_nonvacuous(monkeypatch, tmp_path, variant):
    docs = private_documents()
    if variant == 'extra-unrelated-pod':
        other = copy.deepcopy(docs[('pods', None)]['items'][0])
        other['metadata']['ownerReferences'][0]['uid'] = 'other'
        docs[('pods', None)]['items'].insert(0, other)
    elif variant == 'foreign-only':
        docs[('pods', None)]['items'][0]['metadata']['ownerReferences'][0]['uid'] = 'other'
    elif variant == 'empty':
        docs[('pods', None)]['items'] = []
    docs[('exec', 'board-pod')] = b'retired\n' if variant == 'wrong-worker-response' else b'north-40\n'
    result, _ = execute(monkeypatch, tmp_path, 40, 1, 2, docs)
    assert (result == 0) is (variant in {'reference', 'extra-unrelated-pod'})


def shell_observation(tmp_path, code, app=None, expected='value', variant='reference'):
    home = tmp_path / 'home'
    workspace = home / 'quest'
    binaries = tmp_path / 'bin'
    workspace.mkdir(parents=True, exist_ok=True)
    binaries.mkdir(exist_ok=True)
    facts = workspace / 'facts'
    facts.mkdir(exist_ok=True)
    for name, value in [('baseline-commit', 'abc'), ('expected-dns-address', '10.0.0.9')]:
        (facts / name).write_text(value)
    (facts / 'gateway-target.json').write_text(json.dumps({'url': 'http://private-gateway:8000'}))
    (workspace / 'release-commit').write_text('abc')
    (workspace / 'platform.env').write_text('export GIT_URL=https://git.invalid/station\n')
    settings = {'app': app or {}, 'expected': expected, 'variant': variant}
    config = tmp_path / 'config.json'
    config.write_text(json.dumps(settings))
    kubectl = binaries / 'kubectl'
    kubectl.write_text('''#!/usr/bin/env python3
import json,os,sys
p=json.load(open(os.environ['DQ_TEST_CONFIG']));a=sys.argv[1:]
if a[0]=='rollout':sys.exit(0)
if a[:2]==['get','application']:print(json.dumps(p['app']));sys.exit(0)
if a[:2]==['get','service']:print('10.0.0.53');sys.exit(0)
if a[0]!='exec':sys.exit(91)
selected=(a[a.index('-c')+1] if '-c' in a else ('observer' if p['variant']!='reference' else 'worker'))
good=(selected=='worker' and p['variant']!='wrong') or (selected=='observer' and p['variant']=='wrong')
if any('wrong.station.internal' in x or 'closed.station.internal' in x or x=='http://board:8080' and 'Host: north.station.internal' not in ' '.join(a) and p['expected']=='north-130' for x in a):sys.exit(1)
if 'nslookup' in a:
 if not good:sys.exit(1)
 print('Name: station.internal\\nAddress: 10.0.0.9');sys.exit(0)
print(p['expected'] if good else 'retired')
''')
    kubectl.chmod(0o755)
    git = binaries / 'git'
    git.write_text('#!/bin/sh\nprintf "abc\\trefs/heads/main\\n"\n')
    git.chmod(0o755)
    code = code.replace('/run/dq/facts/0/', str(facts) + '/')
    return subprocess.run(['bash', '-c', 'set -euo pipefail\ncd ~/quest\n' + code],
                          env={**os.environ, 'HOME': str(home), 'PATH': str(binaries) + ':' + os.environ['PATH'], 'DQ_NAMESPACE': 'dq-synthetic', 'DQ_TEST_CONFIG': str(config)},
                          capture_output=True, text=True, timeout=10)


@pytest.mark.parametrize('number,stage,index', [(50, 1, 0), (70, 0, 0), (70, 1, 0), (80, 0, 0), (80, 1, 0), (100, 0, 0), (100, 1, 2)])
@pytest.mark.parametrize('variant', ['reference', 'equivalent', 'wrong', 'parent', 'absolute'])
def test_safe_source_directory_shell(tmp_path, number, stage, index, variant):
    path = {'reference': 'manifests', 'equivalent': '././manifests//', 'wrong': 'other', 'parent': 'a/../manifests', 'absolute': '/manifests'}[variant]
    app = {'spec': {'project': 'station', 'source': {'repoURL': 'https://git.invalid/station', 'path': path, 'targetRevision': 'main'},
                    'destination': {'server': 'https://kubernetes.default.svc', 'namespace': 'dq-synthetic'}, 'syncPolicy': {'automated': {'selfHeal': True, 'prune': True}}},
           'status': {'sync': {'status': 'Synced', 'revision': 'abc'}, 'health': {'status': 'Healthy'}}}
    if number == 50 and variant == 'equivalent':
        app['spec']['destination'].pop('server')
        app['spec']['destination']['name'] = 'in-cluster'
    result = shell_observation(tmp_path, goal(number, stage, index), app=app)
    assert (result.returncode == 0) is (variant in {'reference', 'equivalent'}), result.stdout + result.stderr


@pytest.mark.parametrize('destination,good', [({'name': 'in-cluster'}, True), ({'server': 'https://kubernetes.default.svc'}, True), ({'name': 'other'}, False), ({'server': 'https://other'}, False), ({'server': 'https://kubernetes.default.svc', 'name': 'other'}, False)])
def test_local_destination_identity_shell(tmp_path, destination, good):
    app = {'spec': {'project': 'station', 'source': {'repoURL': 'https://git.invalid/station', 'path': 'manifests', 'targetRevision': 'main'},
                    'destination': dict(destination, namespace='dq-synthetic')},
           'status': {'sync': {'status': 'Synced', 'revision': 'abc'}, 'health': {'status': 'Healthy'}}}
    result = shell_observation(tmp_path, goal(50, 1, 0), app=app)
    assert (result.returncode == 0) is good, result.stdout + result.stderr


@pytest.mark.parametrize('number,stage,index,value', [
    (10, 1, 0, 'release-10'), (30, 1, 0, 'release-30'), (60, 1, 0, 'release-60'), (90, 2, 0, 'release-90'),
    (50, 1, 3, 'north-50'), (70, 1, 5, 'north-70'), (80, 1, 7, 'north-80'), (100, 1, 7, 'north-100'),
    (110, 0, 1, 'dns'), (110, 1, 1, 'dns'), (110, 1, 3, 'north-110'),
    (120, 0, 3, 'dns'), (120, 0, 4, 'ledger-120'), (130, 1, 5, 'north-130'),
])
@pytest.mark.parametrize('variant', ['reference', 'observer-first', 'wrong'])
def test_consumer_exec_selects_worker(tmp_path, number, stage, index, value, variant):
    result = shell_observation(tmp_path, goal(number, stage, index), expected=value, variant=variant)
    assert (result.returncode == 0) is (variant != 'wrong'), result.stdout + result.stderr


@pytest.mark.parametrize('variant', ['reference', 'json', 'runner', 'changed', 'failed', 'missing', 'duplicate', 'duplicate-json', 'unreachable', 'unreachable-json', 'alias-dark', 'alias-failures'])
def test_repeat_delivery_recaps(tmp_path, variant):
    source = goal(20, 1, 2).split("<<'DQ_RECAP'\n", 1)[1].split('\nDQ_RECAP', 1)[0]
    stats = {'app' + str(i): {'changed': 0, 'failed': 0, 'unreachable': 0} for i in (1, 2, 3)}
    if variant == 'changed':
        stats['app2']['changed'] = 1
    elif variant == 'failed':
        stats['app2']['failed'] = 1
    elif variant == 'missing':
        del stats['app3']
    if variant in {'unreachable', 'unreachable-json'}:
        stats['app2']['unreachable'] = 1
    if variant in {'json', 'unreachable-json', 'alias-dark', 'alias-failures'}:
        if variant == 'alias-dark':
            stats['app2']['dark'] = 1
        elif variant == 'alias-failures':
            stats['app2']['failures'] = 1
        text = json.dumps({'stats': stats})
    elif variant == 'duplicate-json':
        text = json.dumps({'stats': stats}).replace('"changed": 0', '"changed": 1, "changed": 0', 1)
    elif variant == 'runner':
        event = {'processed': {h: 1 for h in stats}}
        event.update({key: {h: row[key] for h, row in stats.items()} for key in ('changed', 'failed', 'unreachable')})
        text = json.dumps({'event': 'playbook_on_stats', 'event_data': event})
    else:
        text = 'PLAY RECAP ***\n' + '\n'.join(h + ' : ' + ' '.join(f'{k}={v}' for k, v in row.items()) for h, row in stats.items())
        if variant == 'duplicate':
            text += '\napp1 : changed=0 failed=0 unreachable=0\n'
    (tmp_path / 'second-run.txt').write_text(text)
    result = subprocess.run([os.sys.executable, '-I', '-'], input=source, cwd=tmp_path, text=True, capture_output=True, timeout=5)
    assert (result.returncode == 0) is (variant in {'reference', 'json', 'runner'}), result.stdout + result.stderr
    assert 'Traceback' not in result.stderr


@pytest.mark.parametrize('variant', ['reference', 'extra-fields-newline', 'wrong', 'malformed', 'fetch-failed'])
def test_published_response_failure_is_named_without_traceback(tmp_path, variant):
    home = tmp_path / 'home'
    workspace = home / 'quest'
    binaries = tmp_path / 'bin'
    workspace.mkdir(parents=True)
    binaries.mkdir()
    (workspace / 'platform.env').write_text('')
    data = {'data': {'index.html': 'north-50'}}
    if variant == 'extra-fields-newline':
        data['metadata'] = {'labels': {'unrelated': 'allowed'}}
        data['data'].update({'index.html': 'north-50\n', 'unrelated': 'allowed'})
    elif variant == 'wrong':
        data['data']['index.html'] = 'retired'
    value = workspace / 'published.yaml'
    value.write_text('broken: [' if variant == 'malformed' else yaml.safe_dump(data))
    git = binaries / 'git'
    git.write_text('#!/bin/sh\nif [ "$3" = fetch ]; then exit "$DQ_FETCH_EXIT"; fi\ncat "$DQ_PUBLISHED"\n')
    git.chmod(0o755)
    result = subprocess.run(['bash', '-c', goal(50, 0, 1)], capture_output=True, text=True, timeout=5,
                            env={**os.environ, 'HOME': str(home), 'PATH': str(binaries) + ':' + os.environ['PATH'],
                                 'DQ_PUBLISHED': str(value), 'DQ_FETCH_EXIT': '1' if variant == 'fetch-failed' else '0'})
    good = variant in {'reference', 'extra-fields-newline'}
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    assert 'Traceback' not in result.stderr
    if not good:
        assert '[DQ:published]' in result.stdout
