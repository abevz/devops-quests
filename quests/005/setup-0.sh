set -euo pipefail
cat > prepare.yml <<'DQ_ASSET'
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
DQ_ASSET
ansible-playbook prepare.yml
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
DQ_ASSET
