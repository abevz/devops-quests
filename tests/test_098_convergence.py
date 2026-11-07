"""The integration-only rollout wait keeps the full contract and a fixed budget."""

import json
import itertools
import subprocess
from types import SimpleNamespace

import pytest
import test_quests as matrix


class Clock:
    now = 0

    def monotonic(self):
        return self.now

    def sleep(self, duration):
        self.now += duration


class Bay:
    def __init__(self, clock, statuses, items=(), slices=()):
        self.clock = clock
        self.statuses = iter(statuses)
        self.items = items
        self.slices = slices
        self.calls = 0

    def exec(self, run, script, **kwargs):
        assert script == 'unchanged check'
        assert 0 < kwargs['timeout'] <= 30 - self.clock.now
        self.calls += 1
        return SimpleNamespace(returncode=next(self.statuses, 1), stdout='last response', stderr='')

    def namespace(self, run):
        return 'owned-bay'

    def kube(self, *args, **kwargs):
        assert args[:2] == ('-n', 'owned-bay')
        return SimpleNamespace(stdout=json.dumps({'items': self.slices if 'endpointslices' in args else self.items}))


def test_098_wait_requires_three_consecutive_full_checks(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    bay = Bay(clock, [0, 0, 1, 0, 0, 0])
    matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
    assert bay.calls == 6
    assert clock.now == 5


@pytest.mark.parametrize('item,diagnostic', [
    ({'kind': 'Pod', 'metadata': {'uid': 'old-pod'}}, 'Pods'),
    ({'kind': 'ReplicaSet', 'metadata': {'uid': 'old-rs'}, 'spec': {'replicas': 1}}, 'ReplicaSets'),
    ({'kind': 'ReplicaSet', 'metadata': {'uid': 'old-rs'}, 'spec': {'replicas': 0}, 'status': {'replicas': 1}}, 'ReplicaSets'),
])
def test_098_wait_cannot_hide_stuck_old_rollout(monkeypatch, item, diagnostic):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    bay = Bay(clock, itertools.repeat(0), [item])
    with pytest.raises(pytest.fail.Exception, match=diagnostic):
        matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
    assert clock.now == 30


def test_098_wait_allows_old_pod_to_finish_within_budget(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    bay = Bay(clock, itertools.repeat(0))
    original = bay.kube

    def snapshot(*args, **kwargs):
        bay.items = [] if clock.now >= 7 else [{'kind': 'Pod', 'metadata': {'uid': 'old-pod'}}]
        return original(*args, **kwargs)

    bay.kube = snapshot
    matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
    assert clock.now == 7


@pytest.mark.parametrize('phase', ['Succeeded', 'Failed', 'Running'])
def test_098_wait_accepts_terminating_pod_outside_ready_endpoints(monkeypatch, phase):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    pod = {'kind': 'Pod', 'metadata': {'uid': 'old-pod', 'deletionTimestamp': 'now'}, 'status': {'phase': phase}}
    bay = Bay(clock, [0, 0, 0], [pod])
    matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
    assert bay.calls == 3


@pytest.mark.parametrize('ready,expected', [(True, False), (None, False), (False, True)])
@pytest.mark.parametrize('reference', ['uid', 'name', 'ip'])
def test_098_old_pod_must_leave_ready_endpoints(monkeypatch, ready, expected, reference):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    pod = {'kind': 'Pod', 'metadata': {'uid': 'old-pod', 'name': 'old', 'deletionTimestamp': 'now'}, 'status': {'podIP': '10.0.0.2'}}
    endpoint = {'conditions': {'ready': ready}, 'addresses': ['10.0.0.2' if reference == 'ip' else '10.0.0.3']}
    if reference != 'ip':
        endpoint['targetRef'] = {reference: 'old-pod' if reference == 'uid' else 'old'}
    bay = Bay(clock, itertools.repeat(0), [pod], [{'endpoints': [endpoint]}])
    if expected:
        matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
    else:
        with pytest.raises(pytest.fail.Exception, match='ready endpoints'):
            matrix.wait_098_convergence(bay, {}, 'unchanged check', {'old-pod'}, {'old-rs'})
        assert clock.now == 30


def test_098_checks_all_pods_owned_by_old_replicaset(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    pod = {'kind': 'Pod', 'metadata': {'uid': 'another-old-pod', 'ownerReferences': [{'kind': 'ReplicaSet', 'controller': True, 'uid': 'old-rs'}]}}
    bay = Bay(clock, itertools.repeat(0), [pod])
    with pytest.raises(pytest.fail.Exception, match='terminating'):
        matrix.wait_098_convergence(bay, {}, 'unchanged check', {'original-old-pod'}, {'old-rs'})


def test_098_wait_timeout_reports_last_response(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    bay = Bay(clock, [])
    with pytest.raises(pytest.fail.Exception, match='last response'):
        matrix.wait_098_convergence(bay, {}, 'unchanged check', set(), set())
    assert clock.now == 30
    assert bay.calls == 30


def test_098_wait_handles_probe_timeout(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(matrix, 'time', clock)
    bay = Bay(clock, [])

    def timed_out(*args, **kwargs):
        raise subprocess.TimeoutExpired('probe', kwargs['timeout'])

    bay.exec = timed_out
    with pytest.raises(pytest.fail.Exception, match='timed out'):
        matrix.wait_098_convergence(bay, {}, 'unchanged check', set(), set())
