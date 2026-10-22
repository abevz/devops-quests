set -euo pipefail
mkdir -p group_vars
cat > group_vars/all.yml <<'DQ_ASSET'
route_version: north-ready
DQ_ASSET
cat > group_vars/fleet.yml <<'DQ_ASSET'
route_version: retired
DQ_ASSET
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
