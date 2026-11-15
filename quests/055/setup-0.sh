set -euo pipefail
mkdir -p group_vars
cat > group_vars/all.yml <<'DQ_ASSET'
route_version: north-ready
DQ_ASSET
cat > group_vars/fleet.yml <<'DQ_ASSET'
route_version: retired
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver selected version
    ansible.builtin.copy:
      dest: /srv/site/message
      content: '{{ route_version }}

        '
      mode: '0644'
DQ_ASSET

python3 -I - <<'DQ_PROFILE_SEED'
import json
from pathlib import Path
import yaml
p=Path('inventory.ini');p.write_text(p.read_text()+'\n[east]\napp1\napp2\n\n[west]\napp3\n\n[fleet:children]\neast\nwest\n')
Path('host_vars').mkdir(exist_ok=True)
for path,value in [('group_vars/all.yml',{'route_version':'north-ready','service_profile':{'route':'north-ready','zone':'unassigned','window':'primary'}}),('group_vars/fleet.yml',{'route_version':'retired'}),('group_vars/east.yml',{'service_profile':{'zone':'west'}}),('group_vars/west.yml',{'service_profile':{'zone':'east'}}),('host_vars/app2.yml',{'service_profile':{'window':'standby'}})]:Path(path).write_text(yaml.safe_dump(value,sort_keys=False))
play=yaml.safe_load(Path('rollout.yml').read_text());play[0]['tasks'].append({'name':'Publish effective service profile','ansible.builtin.copy':{'dest':'/srv/site/profile.json','content':'{{ service_profile | to_nice_json }}\n','mode':'0644'}});Path('rollout.yml').write_text(yaml.safe_dump(play,sort_keys=False))
profiles={name:{'route':'north-ready','zone':'east' if name!='app3' else 'west','window':'standby' if name=='app2' else 'primary'} for name in ['app1','app2','app3']}
Path('profile-intent.json').write_text(json.dumps({'message':'north-ready','profilePath':'/srv/site/profile.json','profiles':profiles,'effectiveInventoryAndPublishedProfile':True,'preserveHostExceptions':True,'observesCurrentStateOnly':True},indent=2)+'\n')
DQ_PROFILE_SEED
