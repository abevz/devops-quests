set -euo pipefail
cd ~/quest
cat > credentials.yml <<'DQ_ASSET'
station_token: game-station-secret-69
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars_files:
  - credentials.yml
  tasks:
  - name: Deliver station credential
    ansible.builtin.copy:
      content: '{{ station_token }}

        '
      dest: /srv/site/station-token
      mode: '0644'
    no_log: false
DQ_ASSET
