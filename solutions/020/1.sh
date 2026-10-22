set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  handlers:
  - name: Reload banner
    ansible.builtin.command: dq-service reload
  tasks:
  - name: Deliver release
    ansible.builtin.copy:
      src: release.txt
      dest: /srv/site/message
      mode: '0644'
    notify: Reload banner
DQ_ASSET
ansible-playbook rollout.yml
ansible-playbook rollout.yml
