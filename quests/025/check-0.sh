set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(stat -c %a /srv/site/message)" = 644'
)
[ $? -eq 0 ] || failed=1
(
set -e
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
ansible-playbook rollout.yml >/tmp/idempotence-first.log
ansible-playbook rollout.yml >/tmp/idempotence-second.log
test "$(grep -Ec '^app[123] .*changed=0 .*failed=0' /tmp/idempotence-second.log)" = 3
)
[ $? -eq 0 ] || failed=1
exit "$failed"
