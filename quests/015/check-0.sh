set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'for route in north south east; do test -d "/srv/routes/$route"; test "$(stat -c %a "/srv/routes/$route")" = 750; done'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'for route in north south east; do test -d "/srv/routes/$route"; test "$(stat -c %a "/srv/routes/$route")" = 750; done'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'for route in north south east; do test -d "/srv/routes/$route"; test "$(stat -c %a "/srv/routes/$route")" = 750; done'
