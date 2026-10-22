set -euo pipefail
cd ~/quest
cat > station.yml <<'DQ_ASSET'
route: north
slots: 3
DQ_ASSET
cat > board.j2 <<'DQ_ASSET'
station=unknown route=retired slots=0
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars_files:
  - station.yml
  tasks:
  - name: Render the station board
    ansible.builtin.template:
      src: board.j2
      dest: /srv/site/board
      mode: '0644'
DQ_ASSET
