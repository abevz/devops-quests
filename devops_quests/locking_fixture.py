"""Seed one genuine unsafe state handover using the pinned native clients."""

import hashlib
import json
import re
import shlex
from pathlib import Path

HEADER = '''terraform {
 backend "http" {
  address = "http://127.0.0.1:18787/deployment"
  lock_address = "http://127.0.0.1:18787/deployment"
  unlock_address = "http://127.0.0.1:18787/deployment"
  retry_max = 0
 }
 required_providers {
  local = { source = "registry.terraform.io/hashicorp/local", version = "2.9.0" }
  docker = { source = "registry.terraform.io/kreuzwerker/docker", version = "3.6.2" }
 }
}
provider "docker" {}
resource "local_file" "notice" {
 filename = "/home/hacker/quest/notice.txt"
 content = "north-ready\\n"
}
'''
PROGRESS = 'resource "terraform_data" "progress" { input = "maintenance-complete" }\n'


class LockingFixture:
    def __init__(self, runtime):
        self.r = runtime

    def create(self, run):
        if run['level'] != 87 or not re.fullmatch(r'[a-f0-9]{24}', run['id']):
            raise ValueError('Invalid locking fixture bay')
        r = self.r
        client = r.state / 'bays' / run['id'] / 'client'
        service = client / 'locking-service.py'
        service.write_bytes(Path(__file__).with_name('locking_backend.py').read_bytes())
        service.chmod(0o444)

        def execute(script, *, root=False, timeout=180):
            prefix = 'set -euo pipefail\n' + ('' if root else 'cd ~/quest\n')
            return r.exec(run, prefix + script, root=root, timeout=timeout)

        def write(name, content, *, root=False):
            execute('printf %s ' + shlex.quote(content) + ' > ' + shlex.quote(name), root=root)

        execute('''python3 - <<'START'
import subprocess
subprocess.Popen(['python3', '/run/dq/locking-service.py'], stdin=subprocess.DEVNULL, stdout=open('/var/lib/dq-lock/service.log', 'w'), stderr=subprocess.STDOUT, start_new_session=True)
START
''', root=True)
        execute('''chmod 711 /home/hacker
chmod 755 ~/quest
for attempt in $(seq 1 100); do curl -fsS http://127.0.0.1:18787/diagnostic >/dev/null 2>&1 && break; sleep .05; done
curl -fsS http://127.0.0.1:18787/diagnostic >/dev/null
''')
        write('main.tf', HEADER)
        execute('tofu init -input=false -no-color\ntofu apply -input=false -auto-approve -no-color')
        image = execute("docker image inspect \"$DQ_APP_IMAGE\" --format '{{.Id}}'").stdout.strip()
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', image):
            raise RuntimeError('Missing qualified bay image')
        operation = '''resource "docker_container" "operation" {
 name = "rail-operation"
 image = "''' + image + '''"
 must_run = true
 wait = true
 wait_timeout = 120
 command = ["sleep", "36000"]
 healthcheck {
  test = ["CMD", "test", "-f", "/signal/continue"]
  interval = "1s"
  timeout = "1s"
  start_period = "2m0s"
  retries = 1
 }
 volumes {
  volume_name = "operation-gate"
  container_path = "/signal"
 }
}
'''
        write('main.tf', HEADER + operation)
        execute('''docker volume create operation-gate
python3 - <<'START'
from pathlib import Path
import subprocess
source = "from pathlib import Path; import subprocess; p=subprocess.run(['tofu','apply','-input=false','-auto-approve','-no-color'],stdout=open('failed-apply.log','w'),stderr=subprocess.STDOUT); Path('apply-exit').write_text(str(p.returncode))"
subprocess.Popen(['python3','-c',source], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
START
for attempt in $(seq 1 200); do docker inspect rail-operation >/dev/null 2>&1 && break; sleep .05; done
docker inspect rail-operation >/dev/null
''')
        before = json.loads(execute('curl -fsS http://127.0.0.1:18787/diagnostic').stdout)
        old_id = before['lock']['ID']
        execute('mkdir -p /var/lib/dq-lock/maintenance', root=True)
        write('/var/lib/dq-lock/maintenance/main.tf', HEADER + PROGRESS, root=True)
        execute('cd /var/lib/dq-lock/maintenance\ntofu init -input=false -no-color\ntofu force-unlock -force ' + shlex.quote(old_id) + '\ntofu apply -input=false -auto-approve -no-color\ntouch /var/lib/dq-lock/start-owner', root=True)
        execute('''python3 - <<'WAIT'
import json,time,urllib.request
for attempt in range(200):
    owner=json.load(urllib.request.urlopen('http://127.0.0.1:18787/owner'))
    if owner.get('registered') and owner.get('running'):break
    time.sleep(.05)
else:raise RuntimeError('Native maintenance owner did not acquire its lock')
WAIT
''')
        execute('docker run --rm -v operation-gate:/signal ' + shlex.quote(image) + ''' touch /signal/continue
for attempt in $(seq 1 300); do test -s apply-exit && break; sleep .05; done
test "$(cat apply-exit)" != 0
test -s errored.tfstate
''')
        checkpoint = execute('cat errored.tfstate').stdout
        current = json.loads(execute('curl -fsS http://127.0.0.1:18787/deployment').stdout)
        saved = json.loads(checkpoint)
        physical = json.loads(execute('docker inspect rail-operation').stdout)[0]
        progress = next(x['instances'][0]['attributes']['id'] for x in current['resources'] if x['type'] == 'terraform_data')
        if any(x['type'] == 'terraform_data' for x in saved['resources']) or physical['State']['Health']['Status'] != 'healthy':
            raise RuntimeError('Concurrent incident did not produce distinct real state revisions')
        facts = {'container_id': physical['Id'], 'progress_id': progress, 'lineage': current['lineage'], 'serial': current['serial'], 'backup_sha256': hashlib.sha256(json.dumps(current, sort_keys=True, separators=(',', ':')).encode()).hexdigest(), 'checkpoint_sha256': hashlib.sha256(checkpoint.encode()).hexdigest()}
        (client / 'locking-identities.json').write_text(json.dumps(facts))
        (client / 'locking-identities.json').chmod(0o444)
        write('main.tf', HEADER + PROGRESS + operation)
        write('incident.txt', 'client-A: tofu apply\noperator: tofu force-unlock ' + old_id + '\nclient-B: tofu apply => exit 0\nclient-B: tofu console (active)\nclient-A: failed-apply.log; errored.tfstate\n')
        execute('rm apply-exit')
