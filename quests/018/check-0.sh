set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/board)" = "station=app1 route=north slots=3"; test "$(stat -c %a /srv/site/board)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/board)" = "station=app2 route=north slots=3"; test "$(stat -c %a /srv/site/board)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test "$(cat /srv/site/board)" = "station=app3 route=north slots=3"; test "$(stat -c %a /srv/site/board)" = 644'
