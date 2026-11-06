set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
python3 - <<'DQ_SERIAL'
import yaml
plays=yaml.safe_load(open('rollout.yml'))
assert plays and all(p.get('serial')==1 for p in plays), 'Keep serial: 1 for every maintenance play'
DQ_SERIAL
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app1 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_1]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app2 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_2]' >&2; failed=1; fi
if ! ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/maintenance.txt)" = north-40'; then printf '%s\n' 'app3 /srv/site/maintenance.txt = north-40: ✗ [DQ:maintenance_3]' >&2; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
