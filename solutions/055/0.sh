set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_PROFILE_REFERENCE'
from pathlib import Path
import yaml
Path('group_vars/fleet.yml').write_text('route_version: north-ready\n')
for path,profile in [('group_vars/east.yml',{'route':'north-ready','zone':'east','window':'primary'}),('group_vars/west.yml',{'route':'north-ready','zone':'west','window':'primary'}),('host_vars/app2.yml',{'route':'north-ready','zone':'east','window':'standby'})]:Path(path).write_text(yaml.safe_dump({'service_profile':profile},sort_keys=False))
play=[{'name':'Publish effective station inputs','hosts':'fleet','gather_facts':False,'tasks':[
 {'name':'Deliver selected version','ansible.builtin.copy':{'dest':'/srv/site/message','content':'{{ route_version }}\n','mode':'0644'}},
 {'name':'Publish effective service profile','ansible.builtin.copy':{'dest':'/srv/site/profile.json','content':'{{ service_profile | to_nice_json }}\n','mode':'0644'}}]}]
Path('rollout.yml').write_text(yaml.safe_dump(play,sort_keys=False))
DQ_PROFILE_REFERENCE
ansible-playbook rollout.yml
