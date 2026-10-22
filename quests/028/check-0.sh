set -euo pipefail
cd ~/quest
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'test "$(cat /srv/site/message)" = north-ready && test "$(stat -c %a /srv/site/message)" = 644'
: > rollout-events.jsonl
ansible-playbook rollout.yml >/tmp/serial-check.log
python3 - <<'CHECK'
import json
e=[json.loads(x) for x in open('rollout-events.jsonl')]
h=[x['host'] for x in e if 'host' in x and x['task']=='Deliver the route message']
assert h[-3:]==['app1','app2','app3']
# Every batch starts the task again; one task start for all three hosts is not serial=1.
starts=[x for x in e if 'host' not in x and x['task']=='Deliver the route message']
assert len(starts)>=3
CHECK
