set -euo pipefail
cd ~/quest
mkdir -p roles/station/defaults
cat > roles/station/defaults/main.yml <<'DQ_ASSET'
route: retired
platform: shared
DQ_ASSET
mkdir -p roles/station/tasks
cat > roles/station/tasks/main.yml <<'DQ_ASSET'
- ansible.builtin.copy:
    content: '{{ route }}:{{ platform }}

      '
    dest: /srv/site/role.txt
    mode: '0644'
  name: Render role contract
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- gather_facts: false
  hosts: fleet
  roles:
  - station
DQ_ASSET
