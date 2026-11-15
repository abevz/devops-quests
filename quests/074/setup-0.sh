set -euo pipefail
cd ~/quest
# Generated host keys can precede SSH listener readiness.
dq_transport_deadline=$((SECONDS+10))
for dq_transport_host in app1 app2 app3; do
  until ssh -n -o BatchMode=yes -o ConnectTimeout=1 -o ConnectionAttempts=1 -p 2222 root@"$dq_transport_host-${DQ_NAMESPACE#dq-}" true 2>/dev/null; do
    [ "$SECONDS" -lt "$dq_transport_deadline" ] || exit 1
    sleep 0.2
  done
done
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; printf "%s\n" previous-74 > /srv/site/message; dq-service reload'
cat > rollout.yml <<'DQ_ASSET'
- name: Inspect supplied deployment
  hosts: fleet
  gather_facts: false
  vars:
    delivery_path: /srv/site/message
    release_text: north-74
    inspection_path: /run/quest-service.pid
    service_reload:
    - dq-service
    - reload
  tasks:
  - name: Inspect current process
    ansible.builtin.command:
      argv:
      - cat
      - '{{ inspection_path }}'
    changed_when: false
DQ_ASSET
cat > caller-contract.json <<'DQ_CALLER'
{
  "schema": 1,
  "entrypoint": "rollout.yml",
  "hosts": "fleet",
  "inputs": {
    "delivery_path": "/srv/site/message",
    "release_text": "north-74",
    "inspection_path": "/run/quest-service.pid",
    "service_reload": [
      "dq-service",
      "reload"
    ]
  },
  "localUnprivilegedCaller": true,
  "preserveUnrelatedCallerData": true,
  "observesCurrentProgramCapabilityOnly": true,
  "pendingPreview": {
    "changed": true,
    "skipped": true,
    "mutatesApplicationData": false
  },
  "apply": {
    "deliversCallerRelease": true,
    "refreshesCallerCache": true
  },
  "convergedPreview": {
    "changed": false,
    "skipped": true,
    "mutatesApplicationData": false
  },
  "preserveCallerInspectionInput": true
}
DQ_CALLER
cat > caller-cache.py <<'DQ_CALLER'
"""Provided application adapter: refresh its cached output from the current input."""
from pathlib import Path
import sys

source, cache = map(Path, sys.argv[1:])
cache.write_bytes(source.read_bytes())
DQ_CALLER
