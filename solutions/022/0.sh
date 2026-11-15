set -euo pipefail
cd ~/quest
cat > message.j2 <<'DQ_TEMPLATE'
station={{ inventory_hostname }}
route={{ station_routes[inventory_hostname].active }}
DQ_TEMPLATE
cat > rollout.yml <<'DQ_PLAY'
- name: Render station route inputs
  hosts: fleet
  gather_facts: false
  vars_files:
  - route-declarations.yml
  tasks:
  - name: Render each station banner
    ansible.builtin.template:
      src: message.j2
      dest: /srv/site/message
      mode: '0644'
DQ_PLAY
ansible-playbook rollout.yml
