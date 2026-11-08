"""Keep changes presentation, never the requirements for finishing a stage."""
import asyncio
import subprocess
from types import SimpleNamespace

from aiohttp.test_utils import TestClient, TestServer
import pytest

from devops_quests.catalog import ROOT, Catalog
from devops_quests.engine import Engine
from devops_quests.server import make_app
from devops_quests.store import Store


@pytest.mark.parametrize('value', [0, 1, 'true', None, [], {}])
def test_keep_rejects_non_boolean_metadata(monkeypatch, value):
    import devops_quests.catalog as module
    original = module.yaml.safe_load

    def load(text):
        result = original(text)
        if isinstance(result, dict) and result.get('id') == 1 and 'stages' in result:
            result['stages'][0]['objectives'][0]['keep'] = value
        return result

    monkeypatch.setattr(module.yaml, 'safe_load', load)
    with pytest.raises(ValueError, match='keep must be boolean'):
        Catalog()


@pytest.mark.parametrize('value', [True, False])
def test_catalog_exposes_keep_without_exposing_checks(value):
    catalog = Catalog()
    objectives = catalog.quests[1]['stages'][0]['objectives']
    objectives[0]['keep'] = value
    public = catalog.public(1)['stages'][0]
    assert public['keep'] == [value] + [False] * (len(objectives) - 1)
    assert all('check' not in text for text in public['objectives'])
    del objectives[0]['keep']
    assert catalog.public(1)['stages'][0]['keep'] == [False] * len(objectives)


def test_live_keep_diagnostics_cannot_cross_runs_stages_or_finished_attempts():
    engine = Engine(None, SimpleNamespace(root=ROOT), None)
    diagnostic = {'objective': 1, 'detail': 'Missing [DQ:retained]'}
    engine.keep_observations['first'] = (0, [diagnostic])
    assert engine.keep_failures({'id': 'first', 'stage': 0, 'status': 'active'}) == [diagnostic]
    assert engine.keep_failures({'id': 'second', 'stage': 0, 'status': 'active'}) == []
    assert engine.keep_failures({'id': 'first', 'stage': 1, 'status': 'active'}) == []
    assert engine.keep_failures({'id': 'first', 'stage': 0, 'status': 'passed'}) == []


@pytest.mark.asyncio
async def test_keep_failure_blocks_finish_and_has_live_diagnostics_without_start_confirmation(tmp_path):
    store = Store(tmp_path / 'private/progress.db')
    token = store.login('admin', store.bootstrap().read_text().strip(), 'fixture')
    user = store.session(token)['user_id']
    catalog = Catalog()
    text = catalog.quests[1]['stages'][0]['objectives'][0]['text']
    catalog.quests[1]['stages'] = [{'brief': catalog.quests[1]['stages'][0]['brief'], 'objectives': [
        {'text': text, 'check': 'goal'}, {'text': text, 'check': 'preserve', 'keep': True},
    ]}]

    class Runtime:
        preserve = False
        calls = []
        torn_down = False

        def exec(self, run, script, **kwargs):
            command = script.splitlines()[-1]
            self.calls.append(command)
            passed = command == 'goal' or self.preserve
            return subprocess.CompletedProcess([], 0 if passed else 1, '' if passed else 'Required file is missing [DQ:retained]', '')

        def teardown(self, run):
            self.torn_down = True

    class QuietEngine(Engine):
        async def background(self):
            await asyncio.Event().wait()

    runtime = Runtime()
    engine = QuietEngine(store, catalog, runtime)
    run = store.create_run(user, 1, 'free')
    failed = await engine.poll(run, final=True)
    assert failed['status'] == 'active'
    assert failed['goals'] == [True, False]
    assert failed['check_result']['remaining'][0]['objective'] == 1
    assert engine.keep_failures(failed)[0]['detail'].endswith('[DQ:retained]')
    assert not runtime.torn_down
    assert len([e for e in failed['events'] if e.get('message', {}).get('key') == 'npc.confirmed']) == 1

    client = TestClient(TestServer(make_app(store, catalog, engine)))
    await client.start_server()
    try:
        client.session.cookie_jar.update_cookies({'devops_quests_session': token})
        response = await client.get('/api/state')
        assert response.status == 200
        payload = await response.json()
        assert payload['quest']['stages'][0]['keep'] == [False, True]
        assert payload['run']['keep_failures'] == engine.keep_failures(failed)
        runtime.preserve = True
        passed = await engine.poll(failed, final=True)
        assert passed['status'] == 'passed'
        assert passed['goals'] == [True, True]
        assert runtime.calls == ['goal', 'preserve', 'goal', 'preserve']
        assert runtime.torn_down
        assert engine.keep_failures(passed) == []
        assert len([e for e in passed['events'] if e.get('message', {}).get('key') == 'npc.confirmed']) == 1
    finally:
        await client.close()
