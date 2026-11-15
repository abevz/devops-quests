set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_ROLE_REFERENCE'
from pathlib import Path
import yaml
files={
 'roles/base/meta/main.yml':{'allow_duplicates':True},
 'roles/banner/defaults/main.yml':{'install_root':'/srv/routes','banner_route':'north-ready'},
 'roles/banner/meta/main.yml':{'dependencies':['base']},
 'roles/base/tasks/main.yml':[{'name':'Construct caller directory','ansible.builtin.file':{'path':'{{ install_root }}','state':'directory','mode':'0755'}}],
 'roles/banner/tasks/main.yml':[{'name':'Deliver caller banner','ansible.builtin.copy':{'dest':'{{ install_root }}/current','content':'{{ banner_route }}\n','mode':'0644'}}]
}
for path,value in files.items():Path(path).write_text(yaml.safe_dump(value,sort_keys=False))
DQ_ROLE_REFERENCE
ansible-playbook rollout.yml
