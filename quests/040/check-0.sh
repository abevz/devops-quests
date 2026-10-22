set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'
python3 - <<'DQ_SERIAL'
import yaml
plays=yaml.safe_load(open('rollout.yml'))
assert plays and all(p.get('serial')==1 for p in plays), 'Keep serial: 1 for every maintenance play'
DQ_SERIAL
