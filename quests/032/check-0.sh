set -euo pipefail
cd ~/quest
test "$(cat fleet.txt)" = "$(printf 'app1
app2
app3')"
test "$(stat -c %a fleet.txt)" = 644
ssh -n -o BatchMode=yes -p 2222 root@app1-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
ssh -n -o BatchMode=yes -p 2222 root@app2-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
ssh -n -o BatchMode=yes -p 2222 root@app3-"${DQ_NAMESPACE#dq-}" 'set -eu; test ! -e /srv/site/fleet.txt'
python3 - <<'DQ_DELEGATION'
from pathlib import Path
import jinja2, yaml
plays=yaml.safe_load(Path('rollout.yml').read_text())
copies=[task for play in plays for task in play.get('tasks',[]) if 'ansible.builtin.copy' in task]
assert len(copies)==1, 'Repair the single supplied copy task'
task=copies[0]
assert task.get('delegate_to')=='localhost' and task.get('run_once') is True, 'Delegate one writer to localhost'
content=task['ansible.builtin.copy']['content']
rendered=jinja2.Environment().from_string(content).render(groups={'fleet':['probe-b','probe-a']}, inventory_hostname='probe-a')
assert rendered.splitlines()==['probe-a','probe-b'], 'Derive the report from sorted fleet inventory membership'
DQ_DELEGATION
