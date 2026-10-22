set -euo pipefail
cd ~/quest
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  serial: 1
  tasks:
  - name: Deliver maintenance contract
    ansible.builtin.copy:
      dest: /srv/site/maintenance.txt
      content: 'north-40

        '
      mode: '0644'
DQ_ASSET
ansible-playbook rollout.yml
