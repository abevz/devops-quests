set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Render each station banner
    ansible.builtin.template:
      src: message.j2
      dest: /srv/site/message
      mode: '0644'
DQ_ASSET
ansible-playbook rollout.yml
cat > message.j2 <<'DQ_ASSET'
station={{ inventory_hostname }}
route=north
DQ_ASSET
ansible-playbook rollout.yml
