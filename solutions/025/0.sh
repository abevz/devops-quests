set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail rollout
  hosts: fleet
  gather_facts: false
  tasks:
  - name: Deliver the route message
    ansible.builtin.copy:
      dest: /srv/site/message
      content: 'north-ready

        '
      mode: '0644'
  - name: Read the route message
    ansible.builtin.command: cat /srv/site/message
    changed_when: false
DQ_ASSET
ansible-playbook rollout.yml
