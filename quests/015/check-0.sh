set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/north; test "$(stat -c %a /srv/routes/north)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/south; test "$(stat -c %a /srv/routes/south)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/east; test "$(stat -c %a /srv/routes/east)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/north; test "$(stat -c %a /srv/routes/north)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/south; test "$(stat -c %a /srv/routes/south)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/east; test "$(stat -c %a /srv/routes/east)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/north; test "$(stat -c %a /srv/routes/north)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/south; test "$(stat -c %a /srv/routes/south)" = 750'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test -d /srv/routes/east; test "$(stat -c %a /srv/routes/east)" = 750'
)
[ $? -eq 0 ] || failed=1
exit "$failed"
