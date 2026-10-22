set -euo pipefail
cd ~/quest
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
      mode: '0600'
    no_log: true
DQ_ASSET
ansible-playbook --diff rollout.yml > deployment.log
