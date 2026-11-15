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
cd ~/quest
python3 - <<'ARCHIVE'
import io,tarfile,hashlib
from pathlib import Path
with tarfile.open('recovery.tar','w') as t:
 data=b'north-96\n';i=tarfile.TarInfo('message');i.size=len(data);i.mode=0o644;i.uid=i.gid=0;t.addfile(i,io.BytesIO(data))
Path('artifact.sha256').write_text(hashlib.sha256(Path('recovery.tar').read_bytes()).hexdigest()+'\n')
ARCHIVE

cat > .prepare-consumer.yml <<'SEED'
- hosts: fleet
  gather_facts: false
  tasks:
  - name: Provide application group
    ansible.builtin.group:
      name: restore-consumer
      gid: 1001
  - name: Provide application principal
    ansible.builtin.user:
      name: restore-consumer
      uid: 1001
      group: restore-consumer
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
      dest: /usr/local/libexec/quest-restore-consumer.py
      content: "\"\"\"Provided application: current binding and ledger belong to this\
        \ running instance.\"\"\"\nimport json\nimport os\nimport sys\nfrom http.server\
        \ import BaseHTTPRequestHandler, HTTPServer\nfrom pathlib import Path\n\n\
        binding_path, ledger_path, message_path = map(Path, sys.argv[1:4])\ninstance_nonce\
        \ = sys.argv[4]\n\n\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n\
        \        try:\n            binding = json.loads(binding_path.read_text())\n\
        \            if binding != {'pid': os.getpid(), 'instance': instance_nonce}:\n\
        \                raise ValueError('binding-invalid')\n            ledger =\
        \ json.loads(ledger_path.read_text())\n            result = {'message': message_path.read_text().strip(),\
        \ 'account': ledger['account'], 'balance': ledger['balance'], 'instance':\
        \ instance_nonce}\n            status = 200\n        except (OSError, ValueError,\
        \ KeyError) as error:\n            result = {'error': str(error) if isinstance(error,\
        \ ValueError) else type(error).__name__}\n            status = 503\n     \
        \   body = (json.dumps(result, sort_keys=True) + '\\n').encode()\n       \
        \ self.send_response(status)\n        self.send_header('Content-Type', 'application/json')\n\
        \        self.send_header('Content-Length', str(len(body)))\n        self.end_headers()\n\
        \        self.wfile.write(body)\n\n    def log_message(self, *_):\n      \
        \  pass\n\n\nHTTPServer(('0.0.0.0', 8081), Handler).serve_forever()\n"
      mode: '0555'
  - name: Prepare current private application data
    ansible.builtin.copy:
      dest: /srv/site/tenant.json
      content: '{{ {"account": inventory_hostname, "balance": {"app1": 1701, "app2":
        2802, "app3": 3903}[inventory_hostname]} | to_json }}

        '
      mode: '0600'
  - name: Transfer private data ownership
    ansible.builtin.file:
      path: /srv/site/tenant.json
      owner: restore-consumer
      group: restore-consumer
  - name: Start existing application instance
    ansible.builtin.command:
      argv:
      - /usr/bin/python3
      - -c
      - 'import json,secrets,subprocess

        from pathlib import Path

        nonce=secrets.token_hex(12)

        log=open(''/var/log/restore-consumer.log'',''ab'')

        p=subprocess.Popen([''/usr/bin/python3'',''/usr/local/libexec/quest-restore-consumer.py'',''/srv/site/consumer-binding.json'',''/srv/site/tenant.json'',''/srv/site/message'',nonce],user=1001,group=1001,extra_groups=[],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)

        Path(''/srv/site/consumer-binding.json'').write_text(json.dumps({''pid'':p.pid,''instance'':nonce})+''\n'')

        Path(''/srv/site/consumer-binding.json'').chmod(0o644)

        Path(''/run/restore-consumer.pid'').write_text(str(p.pid)+''\n'')

        '
  - name: Observe actual application listener
    ansible.builtin.wait_for:
      host: 127.0.0.1
      port: 8081
      timeout: 8
SEED
ansible-playbook .prepare-consumer.yml
rm .prepare-consumer.yml
python3 -I - <<'FULL_SNAPSHOT'
import hashlib,io,json,tarfile
from pathlib import Path
contents={'message':b'north-96\n','consumer-binding.json':json.dumps({'pid':0,'instance':'snapshot-old'}).encode()+b'\n','tenant.json':json.dumps({'account':'old-snapshot','balance':0}).encode()+b'\n'}
with tarfile.open('recovery.tar','w') as stream:
 for name,content in contents.items():
  item=tarfile.TarInfo(name);item.size=len(content);item.mode=0o644;item.uid=item.gid=0;stream.addfile(item,io.BytesIO(content))
Path('artifact.sha256').write_text(hashlib.sha256(Path('recovery.tar').read_bytes()).hexdigest()+'\n')
FULL_SNAPSHOT

cat > rollout.yml <<'DQ_PROVIDED'
- name: Configured controlled restore
  hosts: fleet
  gather_facts: false
  serial: 1
  vars:
    expected_sha256: '0000000000000000000000000000000000000000000000000000000000000000'
    restore_root: /srv/site
    restore_owner: root
    restore_group: root
  tasks: []
DQ_PROVIDED
cat > provided-application.py <<'DQ_PROVIDED'
"""Provided application: current binding and ledger belong to this running instance."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

binding_path, ledger_path, message_path = map(Path, sys.argv[1:4])
instance_nonce = sys.argv[4]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            binding = json.loads(binding_path.read_text())
            if binding != {'pid': os.getpid(), 'instance': instance_nonce}:
                raise ValueError('binding-invalid')
            ledger = json.loads(ledger_path.read_text())
            result = {'message': message_path.read_text().strip(), 'account': ledger['account'], 'balance': ledger['balance'], 'instance': instance_nonce}
            status = 200
        except (OSError, ValueError, KeyError) as error:
            result = {'error': str(error) if isinstance(error, ValueError) else type(error).__name__}
            status = 503
        body = (json.dumps(result, sort_keys=True) + '\n').encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()
DQ_PROVIDED
cat > application-contract.json <<'DQ_PROVIDED'
{
  "schema": 1,
  "archive": "recovery.tar",
  "trustedReceipt": "artifact.sha256",
  "port": 8081,
  "process": {
    "name": "restore-consumer",
    "pidFile": "/run/restore-consumer.pid",
    "programPath": "/usr/local/libexec/quest-restore-consumer.py"
  },
  "principal": {
    "name": "restore-consumer",
    "uid": 1001
  },
  "inputs": {
    "binding": "/srv/site/consumer-binding.json",
    "tenantData": "/srv/site/tenant.json",
    "message": "/srv/site/message"
  },
  "readsCurrentInputsOnEachRequest": true,
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
  "preserveLiveBindingAndExistingTenantValues": true,
  "preserveLiveFileOwnerGroupAndMode": true,
  "programInputs": {
    "expected_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "restore_root": "/srv/site",
    "restore_owner": "root",
    "restore_group": "root"
  },
  "callerService": {
    "command": [
      "dq-service",
      "reload"
    ],
    "resolution": "PATH",
    "reloadCopiesDeliveredMessageToConsumerCache": true
  },
  "preserveOtherCallerData": true,
  "certifiedWorkflow": {
    "hosts": "fleet",
    "builtinModules": [
      "copy",
      "file",
      "stat",
      "command",
      "assert",
      "unarchive",
      "template",
      "debug",
      "fail",
      "set_fact",
      "meta"
    ],
    "opaqueRolesAndExternalVariableBindings": false,
    "guardFailureStopsExtraction": true,
    "serviceHandlerCommand": [
      "dq-service",
      "reload"
    ]
  },
  "observesCurrentStateAndProgramCapabilityOnly": true
}
DQ_PROVIDED
python3 -I - <<'DQ_CAPTURE_RESTORE'
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

files = "import hashlib,json,stat\nfrom pathlib import Path\nresult={}\nfor name in ['consumer-binding.json','tenant.json']:\n p=Path('/srv/site')/name;s=p.stat();result[name]={'inode':s.st_ino,'mtime':s.st_mtime_ns,'mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'json':json.loads(p.read_text())}\nprint(json.dumps(result))\n"
states = {}
for host in ('app1', 'app2', 'app3'):
    remote = '/usr/bin/python3 -I -c ' + shlex.quote(files)
    out = subprocess.run(['ssh', '-n', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1', '-o', 'ConnectionAttempts=1', '-p', '2222', 'root@' + host + '-' + os.environ['DQ_NAMESPACE'][3:], remote], capture_output=True, text=True, timeout=4, check=True)
    states[host] = json.loads(out.stdout)
Path('original-live-data.json').write_text(json.dumps(states, indent=2) + '\n')
DQ_CAPTURE_RESTORE
