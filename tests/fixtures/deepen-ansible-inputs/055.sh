set -euo pipefail
cd ~/quest
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
ansible-playbook rollout.yml
cat > group_vars/fleet.yml <<'DQ_ASSET'
route_version: north-ready
DQ_ASSET
ansible-playbook rollout.yml
