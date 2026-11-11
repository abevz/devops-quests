"""Control manuals and initial receipts are real bay inputs, not paid hints."""

import json
import os
import re
import subprocess

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize('number,receipt', [
    (78, 'registry-agent-status.json'), (93, 'vault-agent-status.json'),
    (99, 'control/issuer-status.json'), (121, 'webhook-agent-status.json'),
])
def test_setup_supplies_manual_notice_and_initial_receipt(tmp_path, number, receipt):
    home = tmp_path / 'home'
    quest = home / 'quest'
    quest.mkdir(parents=True)
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    curl = binaries / 'curl'
    curl.write_text('#!/bin/sh\nprintf \'%s\\n\' \'{"initialized":true,"sealed":false,"standby":false}\'\n')
    curl.chmod(0o755)
    setup = (ROOT / f'quests/{number:03}/setup-0.sh').read_text()
    start = setup.index('mkdir -p control\n')
    end = setup.index('> ' + receipt, start) + len('> ' + receipt)
    result = subprocess.run(
        ['bash', '-euc', setup[start:end]], cwd=quest,
        env={**os.environ, 'HOME': str(home), 'VAULT_ADDR': 'http://fixture.invalid',
             'PATH': str(binaries) + ':' + os.environ['PATH']},
        text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert 'control/README.md' in (quest / '.motd').read_text()
    initial = json.loads((quest / receipt).read_text())
    assert initial == ({'initialized': True, 'sealed': False, 'standby': False}
                       if number == 99 else {'status': 'idle'})
    manual = (quest / 'control/README.md').read_text()
    parts = re.split(r'^# (en|ru|de|es|pl)\n', manual, flags=re.M)
    sections = dict(zip(parts[1::2], parts[2::2], strict=True))
    assert set(sections) == {'en', 'ru', 'de', 'es', 'pl'}
    def technical(text):
        return set(re.findall(r'`([^`]+)`', text))
    for text in sections.values():
        assert technical(text) == technical(sections['en'])
        # A schema reference must not embed an incident request to copy.
        assert '{"action"' not in text and '{"policies"' not in text


@pytest.mark.parametrize('interactive,present', [(False, True), (True, False), (True, True)])
def test_login_notice_is_optional_and_interactive(tmp_path, interactive, present):
    quest = tmp_path / 'quest'
    quest.mkdir()
    if present:
        (quest / '.motd').write_text('Station control interface: see ~/quest/control/README.md\n')
    source = (ROOT / 'images/bashrc').read_text().split('if [[ $- == *i*', 1)[1]
    script = 'if [[ $- == *i*' + source
    result = subprocess.run(
        ['bash', '--noprofile', '--norc', '-ic' if interactive else '-c', script],
        env={**os.environ, 'HOME': str(tmp_path)}, text=True, capture_output=True,
    )
    assert result.returncode == 0
    assert ('control/README.md' in result.stdout) == (interactive and present)


@pytest.mark.parametrize('payload', ['invalid-json', '{"action":"other"}', '{"action":"restore-path","target":"foreign"}'])
def test_admission_refuses_invalid_request_with_a_receipt(payload, monkeypatch):
    from devops_quests.admission import Admission
    from devops_quests.platform import Platform

    class Runtime:
        def exec(self, *args, **kwargs):
            return subprocess.CompletedProcess([], 0, payload, '')

        def kube(self, *args, **kwargs):
            pytest.fail('Rejected input must not mutate the webhook')

    receipts = {}
    monkeypatch.setattr(Platform, 'put', lambda self, run, name, text: receipts.update({name: json.loads(text)}))
    Admission(Runtime()).control({'id': 'a' * 24, 'level': 121})
    assert receipts == {'webhook-agent-status.json': {'status': 'rejected'}}
