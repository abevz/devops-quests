set -euo pipefail
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
      mode: '0600'
  - name: Read the route message
    ansible.builtin.command: cat /srv/site/message
    changed_when: true
DQ_ASSET
