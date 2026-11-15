set -euo pipefail
cat > prepare.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-ready

        '
      mode: '0600'
DQ_ASSET
ansible-playbook prepare.yml
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-ready

        '
      mode: '0600'
DQ_ASSET
cat > provided-consumer.py <<'DQ_PROVIDED'
"""Provided application: SIGHUP refreshes the cached file under its own UID."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import signal

message = Path('/srv/site/message')
cached = b'retired\n'


def refresh(*_):
    global cached
    try:
        cached = message.read_bytes()
        print('Cache refreshed', flush=True)
    except OSError as error:
        print(type(error).__name__ + ': ' + str(error), flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(cached)))
        self.end_headers()
        self.wfile.write(cached)

    def log_message(self, *_):
        pass


signal.signal(signal.SIGHUP, refresh)
refresh()
HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()
DQ_PROVIDED
cat > consumer-contract.json <<'DQ_PROVIDED'
{
  "consumers": [
    {
      "name": "banner-reader",
      "pidFile": "/run/quest-banner-reader.pid",
      "programPath": "/usr/local/libexec/quest-banner-reader.py",
      "inputPath": "/srv/site/message",
      "port": 8081
    }
  ],
  "refreshSignal": "SIGHUP",
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
  "response": "north-ready",
  "rootCapabilities": [
    "CHOWN",
    "DAC_OVERRIDE",
    "SETUID",
    "SETGID",
    "SYS_CHROOT",
    "AUDIT_WRITE"
  ],
  "observesCurrentIdentityAndResultsOnly": true
}
DQ_PROVIDED
cat > .prepare-consumer.yml <<'DQ_PROVIDED'
- hosts: fleet
  gather_facts: false
  tasks:
  - name: Create reader group
    ansible.builtin.group:
      name: banner-reader
      gid: 1001
  - name: Create provided reader principal
    ansible.builtin.user:
      name: banner-reader
      uid: 1001
      group: banner-reader
      create_home: false
      shell: /usr/sbin/nologin
      password_lock: true
  - name: Create application program directory
    ansible.builtin.file:
      path: /usr/local/libexec
      state: directory
      mode: '0755'
  - name: Install supplied application
    ansible.builtin.copy:
      dest: /usr/local/libexec/quest-banner-reader.py
      content: "\"\"\"Provided application: SIGHUP refreshes the cached file under\
        \ its own UID.\"\"\"\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\n\
        from pathlib import Path\nimport signal\n\nmessage = Path('/srv/site/message')\n\
        cached = b'retired\\n'\n\n\ndef refresh(*_):\n    global cached\n    try:\n\
        \        cached = message.read_bytes()\n        print('Cache refreshed', flush=True)\n\
        \    except OSError as error:\n        print(type(error).__name__ + ': ' +\
        \ str(error), flush=True)\n\n\nclass Handler(BaseHTTPRequestHandler):\n  \
        \  def do_GET(self):\n        self.send_response(200)\n        self.send_header('Content-Type',\
        \ 'text/plain')\n        self.send_header('Content-Length', str(len(cached)))\n\
        \        self.end_headers()\n        self.wfile.write(cached)\n\n    def log_message(self,\
        \ *_):\n        pass\n\n\nsignal.signal(signal.SIGHUP, refresh)\nrefresh()\n\
        HTTPServer(('0.0.0.0', 8081), Handler).serve_forever()\n"
      mode: '0555'
  - name: Start supplied cache consumer
    ansible.builtin.command:
      argv:
      - /usr/bin/python3
      - -c
      - from pathlib import Path; import subprocess; log=open('/var/log/quest-banner-reader.log','ab');
        p=subprocess.Popen(['/usr/bin/python3','/usr/local/libexec/quest-banner-reader.py'],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,user=1001,group=1001,extra_groups=[],start_new_session=True);
        Path('/run/quest-banner-reader.pid').write_text(str(p.pid)+'\n')
  - name: Wait for actual reader socket
    ansible.builtin.wait_for:
      host: 127.0.0.1
      port: 8081
      timeout: 8
DQ_PROVIDED
ansible-playbook .prepare-consumer.yml
rm .prepare-consumer.yml
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
    assert result[host]['banner-reader']['uid'] == ['1001'] * 4
Path('consumer-identities.json').write_text(json.dumps(result, indent=2) + '\n')
DQ_IDENTITIES
