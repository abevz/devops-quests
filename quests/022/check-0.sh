set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app1 /srv/site/message'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app2 /srv/site/message'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx station=app3 /srv/site/message'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'grep -qx route=north /srv/site/message'
)
[ $? -eq 0 ] || failed=1
exit "$failed"
