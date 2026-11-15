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
for dq_seed_host in app1 app2 app3; do
 dq_seed_route=route=retired
 [ "$dq_seed_host" != app1 ] || dq_seed_route=route=north
 ssh -n -o BatchMode=yes -p 2222 root@"$dq_seed_host-${DQ_NAMESPACE#dq-}" "set -eu; mkdir -p /srv/site/config; chmod 755 /srv/site/config; printf '%s\n' retired-79 > /srv/site/message; chmod 644 /srv/site/message; printf '%s\n' '$dq_seed_route' > /srv/site/config/route; chmod 644 /srv/site/config/route; dq-service reload"
 dq_seed_deadline=$((SECONDS+8))
 until [ "$(curl -fsS --max-time 2 "http://$dq_seed_host-${DQ_NAMESPACE#dq-}:8080")" = retired-79 ]; do
  [ "$SECONDS" -lt "$dq_seed_deadline" ] || exit 1
  sleep 0.2
 done
 ssh -n -o BatchMode=yes -p 2222 root@"$dq_seed_host-${DQ_NAMESPACE#dq-}" "printf '%s\n' north-79 > /srv/site/message; chmod 644 /srv/site/message"
 if [ "$dq_seed_host" = app1 ]; then
  ssh -n -o BatchMode=yes -p 2222 root@"$dq_seed_host-${DQ_NAMESPACE#dq-}" 'dq-service reload'
  dq_seed_deadline=$((SECONDS+8))
  until [ "$(curl -fsS --max-time 2 "http://$dq_seed_host-${DQ_NAMESPACE#dq-}:8080")" = north-79 ]; do
   [ "$SECONDS" -lt "$dq_seed_deadline" ] || exit 1
   sleep 0.2
  done
 fi
done

cat > rollout.yml <<'DQ_PROVIDED'
- name: Configured fleet recovery
  hosts: fleet
  gather_facts: false
  vars:
    delivery_root: /srv/site
    expected_message: north-79
    expected_route: route=north
    service_observe:
    - curl
    - -fsS
    - --max-time
    - '2'
    - http://127.0.0.1:8080/
    service_reload:
    - dq-service
    - reload
  tasks: []
DQ_PROVIDED
cat > caller-contract.json <<'DQ_PROVIDED'
{
  "schema": 1,
  "entrypoint": "rollout.yml",
  "hosts": "fleet",
  "inputs": {
    "delivery_root": "/srv/site",
    "expected_message": "north-79",
    "expected_route": "route=north",
    "service_observe": [
      "curl",
      "-fsS",
      "--max-time",
      "2",
      "http://127.0.0.1:8080/"
    ],
    "service_reload": [
      "dq-service",
      "reload"
    ]
  },
  "localUnprivilegedCaller": true,
  "testMessage": "south-probe",
  "testRoute": "route=south",
  "initialCallerState": {
    "message": "desired",
    "directoryMode": "0700",
    "route": "desired",
    "consumerCache": "retired-probe"
  },
  "preserveOtherCallerData": true,
  "secondApply": {
    "changed": 0,
    "failed": 0,
    "unreachable": 0,
    "applicationDataUnchanged": true
  },
  "observesCurrentProgramCapabilityOnly": true
}
DQ_PROVIDED
cat > caller-cache.py <<'DQ_PROVIDED'
"""Provided application adapter: refresh its cached output from the current input."""
from pathlib import Path
import sys

source, cache = map(Path, sys.argv[1:])
cache.write_bytes(source.read_bytes())
DQ_PROVIDED
