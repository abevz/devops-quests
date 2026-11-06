set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app1 route=north slots=3'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app2 route=north slots=3'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/board)" = '"'"'station=app3 route=north slots=3'"'"''
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/board)" = 644'
)
[ $? -eq 0 ] || failed=1
exit "$failed"
