set -euo pipefail
cd ~/quest
cat > credentials.yml <<'DQ_ASSET'
station_token: game-station-secret-69
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars_files:
  - credentials.yml
  tasks:
  - name: Deliver station credential
    ansible.builtin.copy:
      content: '{{ station_token }}

        '
      dest: /srv/site/station-token
      mode: '0644'
    no_log: false
DQ_ASSET
cat > provided-consumer.py <<'DQ_PROVIDED'
"""Provided consumer: authorize against its private file under its fixed UID."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import hmac
import sys

credential = Path(sys.argv[1])
port = int(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            value = credential.read_text().rstrip('\n')
        except (OSError, UnicodeError) as error:
            print(type(error).__name__, flush=True)
            status, body = 503, b'credential unavailable\n'
        else:
            valid = hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer '+value)
            status, body = (200, b'credential-ready\n') if valid else (401, b'unauthorized\n')
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


HTTPServer(('0.0.0.0', port), Handler).serve_forever()
DQ_PROVIDED
cat > consumer-contract.json <<'DQ_PROVIDED'
{
  "consumers": [
    {
      "name": "credential-a",
      "pidFile": "/run/credential-a.pid",
      "programPath": "/usr/local/libexec/quest-credential-reader.py",
      "inputPath": "/srv/site/station-token",
      "port": 8081
    },
    {
      "name": "credential-b",
      "pidFile": "/run/credential-b.pid",
      "programPath": "/usr/local/libexec/quest-credential-reader.py",
      "inputPath": "/srv/relay/station-token",
      "port": 8082
    }
  ],
  "outsider": {
    "name": "credential-outsider",
    "uid": 1003
  },
  "authentication": "Authorization: Bearer <station_token>",
  "response": "credential-ready",
  "readAndWriteDeniedToOtherConsumersAndOutsider": true,
  "preserve": [
    "pid",
    "starttime",
    "uid",
    "gid",
    "groups",
    "caps",
    "command",
    "code"
  ],
  "rootCapabilities": [
    "CHOWN",
    "DAC_OVERRIDE",
    "SETUID",
    "SETGID",
    "SYS_CHROOT",
    "AUDIT_WRITE"
  ],
  "observesCurrentAccessIdentityAndResultsOnly": true
}
DQ_PROVIDED
cat > .prepare-consumers.yml <<'DQ_PROVIDED'
- hosts: fleet
  gather_facts: false
  tasks:
  - name: Create provided principal group
    ansible.builtin.group:
      name: credential-a
      gid: 1001
  - name: Create provided principal
    ansible.builtin.user:
      name: credential-a
      uid: 1001
      group: credential-a
      create_home: false
      shell: /usr/sbin/nologin
      password_lock: true
  - name: Create provided principal group
    ansible.builtin.group:
      name: credential-b
      gid: 1002
  - name: Create provided principal
    ansible.builtin.user:
      name: credential-b
      uid: 1002
      group: credential-b
      create_home: false
      shell: /usr/sbin/nologin
      password_lock: true
  - name: Create provided principal group
    ansible.builtin.group:
      name: credential-outsider
      gid: 1003
  - name: Create provided principal
    ansible.builtin.user:
      name: credential-outsider
      uid: 1003
      group: credential-outsider
      create_home: false
      shell: /usr/sbin/nologin
      password_lock: true
  - name: Create second input directory
    ansible.builtin.file:
      path: /srv/relay
      state: directory
      mode: '0755'
  - name: Create application program directory
    ansible.builtin.file:
      path: /usr/local/libexec
      state: directory
      mode: '0755'
  - name: Provide credential consumer
    ansible.builtin.copy:
      dest: /usr/local/libexec/quest-credential-reader.py
      content: "\"\"\"Provided consumer: authorize against its private file under\
        \ its fixed UID.\"\"\"\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\n\
        from pathlib import Path\nimport hmac\nimport sys\n\ncredential = Path(sys.argv[1])\n\
        port = int(sys.argv[2])\n\n\nclass Handler(BaseHTTPRequestHandler):\n    def\
        \ do_GET(self):\n        try:\n            value = credential.read_text().rstrip('\\\
        n')\n        except (OSError, UnicodeError) as error:\n            print(type(error).__name__,\
        \ flush=True)\n            status, body = 503, b'credential unavailable\\\
        n'\n        else:\n            valid = hmac.compare_digest(self.headers.get('Authorization',\
        \ ''), 'Bearer '+value)\n            status, body = (200, b'credential-ready\\\
        n') if valid else (401, b'unauthorized\\n')\n        self.send_response(status)\n\
        \        self.send_header('Content-Length', str(len(body)))\n        self.end_headers()\n\
        \        self.wfile.write(body)\n\n    def log_message(self, *_):\n      \
        \  pass\n\n\nHTTPServer(('0.0.0.0', port), Handler).serve_forever()\n"
      mode: '0555'
  - name: Provide stale input
    ansible.builtin.copy:
      dest: /srv/site/station-token
      content: 'retired

        '
      mode: '0644'
  - name: Start existing private consumer
    ansible.builtin.command:
      argv:
      - /usr/bin/python3
      - -c
      - from pathlib import Path; import subprocess; log=open('/var/log/credential-a.log','ab');
        p=subprocess.Popen(['/usr/bin/python3','/usr/local/libexec/quest-credential-reader.py','/srv/site/station-token','8081'],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,user=1001,group=1001,extra_groups=[],start_new_session=True);
        Path('/run/credential-a.pid').write_text(str(p.pid)+'\n')
  - name: Wait for consumer
    ansible.builtin.wait_for:
      host: 127.0.0.1
      port: 8081
      timeout: 8
  - name: Provide stale input
    ansible.builtin.copy:
      dest: /srv/relay/station-token
      content: 'retired

        '
      mode: '0644'
  - name: Start existing private consumer
    ansible.builtin.command:
      argv:
      - /usr/bin/python3
      - -c
      - from pathlib import Path; import subprocess; log=open('/var/log/credential-b.log','ab');
        p=subprocess.Popen(['/usr/bin/python3','/usr/local/libexec/quest-credential-reader.py','/srv/relay/station-token','8082'],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,user=1002,group=1002,extra_groups=[],start_new_session=True);
        Path('/run/credential-b.pid').write_text(str(p.pid)+'\n')
  - name: Wait for consumer
    ansible.builtin.wait_for:
      host: 127.0.0.1
      port: 8082
      timeout: 8
DQ_PROVIDED
ansible-playbook .prepare-consumers.yml
rm .prepare-consumers.yml
python3 -I - <<'DQ_IDENTITIES'
import json, os, shlex, subprocess
from pathlib import Path
observer = "import hashlib\nimport json\nimport sys\nfrom pathlib import Path\n\nresult = {}\nfor item in json.loads(sys.argv[1]):\n    pid = Path(item['pidFile']).read_text().strip()\n    proc = Path('/proc') / pid\n    status = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines() if ':' in line)\n    result[item['name']] = {\n        'pid': pid,\n        'starttime': (proc / 'stat').read_text().rsplit(') ', 1)[1].split()[19],\n        'uid': status['Uid'].split(),\n        'gid': status['Gid'].split(),\n        'groups': status['Groups'].split(),\n        'caps': {key: status[key].strip() for key in ('CapInh', 'CapPrm', 'CapEff', 'CapBnd', 'CapAmb')},\n        'command': (proc / 'cmdline').read_bytes().decode().split(chr(0)),\n        'code': hashlib.sha256(Path(item['programPath']).read_bytes()).hexdigest(),\n    }\nprint(json.dumps(result))\n"
consumers = json.loads(Path('consumer-contract.json').read_text())['consumers']
result = {}
for host in ('app1', 'app2', 'app3'):
    remote = '/usr/bin/python3 -c ' + shlex.quote(observer) + ' ' + shlex.quote(json.dumps(consumers))
    out = subprocess.run(['ssh', '-n', '-o', 'BatchMode=yes', '-p', '2222', 'root@' + host + '-' + os.environ['DQ_NAMESPACE'][3:], remote], check=True, capture_output=True, text=True, timeout=4)
    result[host] = json.loads(out.stdout)
    for index, item in enumerate(consumers):
        assert result[host][item['name']]['uid'] == [str(1001 + index)] * 4
Path('consumer-identities.json').write_text(json.dumps(result, indent=2) + '\n')
DQ_IDENTITIES
