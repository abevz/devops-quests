set -euo pipefail
cd ~/quest
# Host keys may exist before the managed SSH listeners are ready.
dq_transport_deadline=$((SECONDS+10))
for dq_transport_host in app1 app2 app3; do
 until ssh -n -o BatchMode=yes -o ConnectTimeout=1 -o ConnectionAttempts=1 -p 2222 root@"$dq_transport_host-${DQ_NAMESPACE#dq-}" true 2>/dev/null; do
  [ "$SECONDS" -lt "$dq_transport_deadline" ] || exit 1
  sleep 0.2
 done
done
set -euo pipefail

cat > .prepare-application.yml <<'SEED'
- hosts: fleet
  gather_facts: false
  vars:
    publisher_inputs:
      release_path: /srv/site/message
      sha256: f5c7d9bf0eab8e9144f7c8716cccf61839dc53d39841c823cc63e075724cf7a1
      generation: approved-86
    reader_url: http://app1-{{ lookup('env', 'DQ_NAMESPACE') | regex_replace('^dq-',
      '') }}:8080/
  tasks:
  - name: Provide application group
    ansible.builtin.group:
      name: publication-app
      gid: 1001
  - name: Provide application principal
    ansible.builtin.user:
      name: publication-app
      uid: 1001
      group: publication-app
      create_home: false
      shell: /usr/sbin/nologin
      password_lock: true
  - name: Provide program directory
    ansible.builtin.file:
      path: /usr/local/libexec
      state: directory
      mode: '0755'
  - name: Provide actual application
    ansible.builtin.copy:
      dest: /usr/local/libexec/quest-propagation-consumer.py
      content: "\"\"\"Provided publisher/consumer application with explicit refresh\
        \ and observable cache state.\"\"\"\nimport hashlib\nimport hmac\nimport json\n\
        import signal\nimport sys\nimport urllib.request\nfrom http.server import\
        \ BaseHTTPRequestHandler, HTTPServer\nfrom pathlib import Path\n\nrole = sys.argv[1]\n\
        configuration = Path(sys.argv[2])\ncredential = Path(sys.argv[3]) if len(sys.argv)\
        \ > 3 else None\ncache = None\nfailure = None\nopener = urllib.request.build_opener(urllib.request.ProxyHandler({}))\n\
        \n\nclass DigestMismatch(ValueError):\n    pass\n\n\ndef refresh(*_):\n  \
        \  global cache, failure\n    try:\n        inputs = json.loads(configuration.read_text())\n\
        \        if role == 'publisher':\n            candidate = dict(inputs)\n \
        \           if 'release_path' in inputs:\n                candidate['release']\
        \ = Path(inputs['release_path']).read_text()\n            origin = 'local'\n\
        \        else:\n            headers = {'Authorization': 'Bearer ' + credential.read_text().strip()}\
        \ if credential else {}\n            with opener.open(urllib.request.Request(inputs['upstream'],\
        \ headers=headers), timeout=3) as response:\n                candidate = json.loads(response.read(65536))['data']\n\
        \            origin = inputs['upstream']\n        release, generation = candidate['release'],\
        \ candidate['generation']\n        if not isinstance(release, str) or not\
        \ isinstance(generation, str):\n            raise ValueError('invalid publication\
        \ fields')\n        digest = hashlib.sha256(release.encode()).hexdigest()\n\
        \        if not hmac.compare_digest(candidate['sha256'], digest):\n      \
        \      raise DigestMismatch()\n        cache = {'release': release, 'generation':\
        \ generation, 'sha256': digest, 'origin': origin}\n        failure = None\n\
        \        print('refresh accepted', flush=True)\n    except (OSError, ValueError,\
        \ KeyError, TypeError) as error:\n        failure = type(error).__name__\n\
        \        print('refresh failed: ' + failure, flush=True)\n\n\nclass Handler(BaseHTTPRequestHandler):\n\
        \    def do_GET(self):\n        if credential:\n            try:\n       \
        \         expected = 'Bearer ' + credential.read_text().strip()\n        \
        \    except OSError as error:\n                self.reply(503, {'error': type(error).__name__})\n\
        \                return\n            if not hmac.compare_digest(self.headers.get('Authorization',\
        \ ''), expected):\n                self.reply(401, {'error': 'Unauthorized'})\n\
        \                return\n        ready = cache is not None and failure is\
        \ None\n        self.reply(200 if ready else 503, {'ready': ready, 'role':\
        \ role, 'error': failure, 'data': cache})\n\n    def reply(self, status, result):\n\
        \        body = (json.dumps(result, sort_keys=True) + '\\n').encode()\n  \
        \      self.send_response(status)\n        self.send_header('Content-Type',\
        \ 'application/json')\n        self.send_header('Content-Length', str(len(body)))\n\
        \        self.end_headers()\n        self.wfile.write(body)\n\n    def log_message(self,\
        \ *_):\n        pass\n\n\nsignal.signal(signal.SIGHUP, refresh)\nrefresh()\n\
        HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()\n"
      mode: '0555'
  - name: Provide deployment interface input
    ansible.builtin.copy:
      dest: /srv/site/application.json
      content: '{{ (publisher_inputs if inventory_hostname == ''app1'' else {''upstream'':
        reader_url}) | to_json }}

        '
      mode: '0644'
  - name: Start supplied application instance
    ansible.builtin.command:
      argv:
      - /usr/bin/python3
      - -c
      - 'from pathlib import Path

        import subprocess

        role=''{{ "publisher" if inventory_hostname == "app1" else "reader" }}''

        args=[''/usr/bin/python3'',''/usr/local/libexec/quest-propagation-consumer.py'',role,''/srv/site/application.json'']

        log=open(''/var/log/propagation-consumer.log'',''ab'')

        p=subprocess.Popen(args,user=1001,group=1001,extra_groups=[],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)

        Path(''/run/propagation-consumer.pid'').write_text(str(p.pid)+''\n'')

        '
  - name: Observe application listener
    ansible.builtin.wait_for:
      host: 127.0.0.1
      port: 8081
      timeout: 8
SEED
ansible-playbook .prepare-application.yml
rm .prepare-application.yml
cat > previous.txt <<'PREVIOUS'
stable-ready
PREVIOUS
cat > candidate.txt <<'CANDIDATE'
candidate
CANDIDATE

cat > rollout.yml <<'DQ_PROVIDED'
- name: Configured recovery and publication
  hosts: fleet
  gather_facts: false
  tasks: []
DQ_PROVIDED
cat > provided-application.py <<'DQ_PROVIDED'
"""Provided publisher/consumer application with explicit refresh and observable cache state."""
import hashlib
import hmac
import json
import signal
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

role = sys.argv[1]
configuration = Path(sys.argv[2])
credential = Path(sys.argv[3]) if len(sys.argv) > 3 else None
cache = None
failure = None
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class DigestMismatch(ValueError):
    pass


def refresh(*_):
    global cache, failure
    try:
        inputs = json.loads(configuration.read_text())
        if role == 'publisher':
            candidate = dict(inputs)
            if 'release_path' in inputs:
                candidate['release'] = Path(inputs['release_path']).read_text()
            origin = 'local'
        else:
            headers = {'Authorization': 'Bearer ' + credential.read_text().strip()} if credential else {}
            with opener.open(urllib.request.Request(inputs['upstream'], headers=headers), timeout=3) as response:
                candidate = json.loads(response.read(65536))['data']
            origin = inputs['upstream']
        release, generation = candidate['release'], candidate['generation']
        if not isinstance(release, str) or not isinstance(generation, str):
            raise ValueError('invalid publication fields')
        digest = hashlib.sha256(release.encode()).hexdigest()
        if not hmac.compare_digest(candidate['sha256'], digest):
            raise DigestMismatch()
        cache = {'release': release, 'generation': generation, 'sha256': digest, 'origin': origin}
        failure = None
        print('refresh accepted', flush=True)
    except (OSError, ValueError, KeyError, TypeError) as error:
        failure = type(error).__name__
        print('refresh failed: ' + failure, flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if credential:
            try:
                expected = 'Bearer ' + credential.read_text().strip()
            except OSError as error:
                self.reply(503, {'error': type(error).__name__})
                return
            if not hmac.compare_digest(self.headers.get('Authorization', ''), expected):
                self.reply(401, {'error': 'Unauthorized'})
                return
        ready = cache is not None and failure is None
        self.reply(200 if ready else 503, {'ready': ready, 'role': role, 'error': failure, 'data': cache})

    def reply(self, status, result):
        body = (json.dumps(result, sort_keys=True) + '\n').encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


signal.signal(signal.SIGHUP, refresh)
refresh()
HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()
DQ_PROVIDED
cat > application-contract.json <<'DQ_PROVIDED'
{
  "schema": 1,
  "sourceHost": "app1",
  "roles": {
    "app1": "publisher",
    "app2": "reader",
    "app3": "reader"
  },
  "port": 8081,
  "configuration": "/srv/site/application.json",
  "process": {
    "name": "publication-app",
    "pidFile": "/run/propagation-consumer.pid",
    "programPath": "/usr/local/libexec/quest-propagation-consumer.py"
  },
  "principal": {
    "name": "publication-app",
    "uid": 1001
  },
  "refreshSignal": "SIGHUP",
  "rootCapabilities": [
    "CHOWN",
    "DAC_OVERRIDE",
    "SETUID",
    "SETGID",
    "SYS_CHROOT",
    "AUDIT_WRITE"
  ],
  "publication": {
    "release": "stable-ready\n",
    "sha256": "f5c7d9bf0eab8e9144f7c8716cccf61839dc53d39841c823cc63e075724cf7a1",
    "generation": "approved-86"
  },
  "authentication": false,
  "controllerArtifact": "previous.txt",
  "preserveProcessFields": [
    "pid",
    "starttime",
    "uid",
    "gid",
    "groups",
    "caps",
    "command",
    "code"
  ],
  "observesCurrentResultsAndIdentityOnly": true
}
DQ_PROVIDED
python3 -I - <<'DQ_CAPTURE_APPLICATIONS'
import json
import os
import shlex
import subprocess
from pathlib import Path

observer = "import hashlib\nimport json\nimport sys\nfrom pathlib import Path\n\nresult = {}\nfor item in json.loads(sys.argv[1]):\n    pid = Path(item['pidFile']).read_text().strip()\n    proc = Path('/proc') / pid\n    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)\n    result[item['name']] = {\n        'pid': pid,\n        'starttime': (proc / 'stat').read_text().rsplit(') ', 1)[1].split()[19],\n        'uid': status['Uid'].split(),\n        'gid': status['Gid'].split(),\n        'groups': status['Groups'].split(),\n        'caps': {key: status[key].strip() for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb')},\n        'command': (proc / 'cmdline').read_bytes().decode().split(chr(0)),\n        'code': hashlib.sha256(Path(item['programPath']).read_bytes()).hexdigest(),\n    }\nprint(json.dumps(result))\n"
contract = json.loads(Path('application-contract.json').read_text())
identities = {}
for host in ('app1', 'app2', 'app3'):
    remote = '/usr/bin/python3 -I -c ' + shlex.quote(observer) + ' ' + shlex.quote(json.dumps([contract['process']]))
    out = subprocess.run(['ssh', '-n', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1', '-o', 'ConnectionAttempts=1', '-p', '2222', 'root@' + host + '-' + os.environ['DQ_NAMESPACE'][3:], remote], capture_output=True, text=True, timeout=4, check=True)
    identities[host] = json.loads(out.stdout)
    assert identities[host][contract['process']['name']]['uid'] == ['1001'] * 4
Path('original-application-identities.json').write_text(json.dumps(identities, indent=2) + '\n')
DQ_CAPTURE_APPLICATIONS
