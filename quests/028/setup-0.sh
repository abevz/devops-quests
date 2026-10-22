set -euo pipefail
mkdir -p callback_plugins
cat > callback_plugins/rail_trace.py <<'DQ_ASSET'
from ansible.plugins.callback import CallbackBase
import json, os, time
class CallbackModule(CallbackBase):
 CALLBACK_VERSION=2.0
 CALLBACK_TYPE='aggregate'
 CALLBACK_NAME='rail_trace'
 CALLBACK_NEEDS_ENABLED=True
 def v2_playbook_on_task_start(self, task, is_conditional):
  with open(os.path.expanduser('~/quest/rollout-events.jsonl'),'a') as f: f.write(json.dumps({'task':task.get_name(),'at':time.time()})+'\n')
 def v2_runner_on_ok(self, result):
  with open(os.path.expanduser('~/quest/rollout-events.jsonl'),'a') as f: f.write(json.dumps({'host':result._host.get_name(),'task':result._task.get_name(),'at':time.time()})+'\n')
DQ_ASSET
printf 'callbacks_enabled=rail_trace\ncallback_plugins=./callback_plugins\n' >> ansible.cfg
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'south-ready

        '
      mode: '0644'
DQ_ASSET
