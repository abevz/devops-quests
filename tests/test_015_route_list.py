"""The outcome check follows supplied route data without inspecting loop syntax."""

import json
import os
import subprocess
import sys

import pytest

from devops_quests.catalog import ROOT


@pytest.mark.parametrize('fault', [None, 'app1-mode', 'app2-mode', 'app3-missing'])
@pytest.mark.parametrize('routes,existing,expected', [
    (['north', 'south', 'east'], [], False),
    (['north', 'south', 'east'], ['north', 'south', 'east'], True),
    (['north', 'south', 'east', 'west'], ['north', 'south', 'east'], False),
    (['north', 'south', 'east', 'west'], ['north', 'south', 'east', 'west'], True),
    ([], [], False),
    (['../../escape'], [], False),
])
def test_015_checks_current_list_on_every_host(tmp_path, routes, existing, expected, fault):
    home = tmp_path / 'home'
    quest = home / 'quest'
    quest.mkdir(parents=True)
    (quest / 'routes.yml').write_text(json.dumps({'routes': routes}))
    hosts = tmp_path / 'hosts'
    for host in ('app1', 'app2', 'app3'):
        (hosts / host).mkdir(parents=True)
        for route in existing:
            (hosts / host / route).mkdir(mode=0o750)
    if fault and existing:
        host, kind = fault.split('-')
        path = hosts / host / existing[0]
        if kind == 'missing':
            path.rmdir()
        else:
            path.chmod(0o700)
        expected = False
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    ssh = binaries / 'ssh'
    ssh.write_text(f'#!{sys.executable}\n'
                   'import os,subprocess,sys\n'
                   "host = sys.argv[-2].removeprefix('root@').split('-')[0]\n"
                   "script = sys.argv[-1].replace('/srv/routes/', os.environ['DQ_TEST_HOSTS'] + '/' + host + '/')\n"
                   "raise SystemExit(subprocess.call(['bash', '-c', script]))\n")
    ssh.chmod(0o755)
    result = subprocess.run(
        ['bash', str(ROOT / 'quests/015/check-0.sh')], cwd=quest, text=True, capture_output=True,
        env={**os.environ, 'HOME': str(home), 'DQ_NAMESPACE': 'dq-fixture',
             'DQ_TEST_HOSTS': str(hosts), 'PATH': str(binaries) + ':' + os.environ['PATH']},
    )
    assert (result.returncode == 0) == expected, result.stdout + result.stderr
    if not expected:
        assert '[DQ:' in result.stdout
