set -euo pipefail
cd ~/quest
cat > routes.yml <<'DQ_ASSET'
routes:
- north
- south
- east
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- name: SignalRail station configuration
  hosts: fleet
  gather_facts: false
  vars_files:
  - routes.yml
  tasks:
  - name: Prepare route folders
    ansible.builtin.file:
      path: /srv/routes/{{ item }}
      state: file
      mode: '0750'
    loop: '{{ routes }}'
DQ_ASSET
