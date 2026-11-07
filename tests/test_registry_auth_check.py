"""Registry diagnostics distinguish encoding from credentials without leaking them."""

import base64
import json
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def credential_result(secret):
    source = yaml.safe_load((ROOT / 'quests/042/quest.yaml').read_text())['stages'][0]['objectives'][2]['check']
    program = source.split("<<'DQ_REGISTRY_CREDENTIALS'\n", 1)[1].split('\nDQ_REGISTRY_CREDENTIALS', 1)[0]
    return subprocess.run(
        [sys.executable, '-I', '-', json.dumps(secret), 'registry.invalid', 'reader', 'synthetic-password'],
        input=program,
        capture_output=True,
        text=True,
        timeout=5,
    )


def credential_secret(corruption=None, secret_type='kubernetes.io/dockerconfigjson'):
    content = 'reader:wrong-password' if corruption == 'wrong' else 'reader:synthetic-password'
    auth = base64.b64encode(content.encode()).decode()
    if corruption == 'auth':
        auth += '$'
    config = json.dumps({'auths': {'registry.invalid': {'auth': auth}}}).encode()
    outer = base64.b64encode(config).decode()
    if corruption == 'outer':
        outer += '$'
    return {'type': secret_type, 'data': {'.dockerconfigjson': outer}}


@pytest.mark.parametrize(
    ('corruption', 'expected_marker'),
    [(None, None), ('outer', 'outer'), ('auth', 'auth'), ('wrong', 'credentials')],
)
def test_registry_auth_diagnostics_reject_encoding_and_credential_errors(corruption, expected_marker):
    result = credential_result(credential_secret(corruption))
    assert (result.returncode == 0) is (expected_marker is None)
    if expected_marker is None:
        assert result.stdout == ''
    else:
        assert result.stdout.count('\n') == 1
        assert result.stdout.rstrip().endswith(f'[DQ:{expected_marker}]')
    for private in ['synthetic-password', 'wrong-password', 'reader:']:
        assert private not in result.stdout + result.stderr


@pytest.mark.parametrize(('secret_type', 'accepted'), [('kubernetes.io/dockerconfigjson', True), ('Opaque', False)])
def test_registry_secret_type(secret_type, accepted):
    result = credential_result(credential_secret(secret_type=secret_type))
    assert (result.returncode == 0) is accepted
    if not accepted:
        assert result.stdout.count('\n') == 1
        assert result.stdout.rstrip().endswith('[DQ:secret_type]')
    assert 'synthetic-password' not in result.stdout + result.stderr
