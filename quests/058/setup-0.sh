set -euo pipefail
mkdir -p roles/base/tasks roles/banner/tasks roles/banner/meta
cat > roles/base/tasks/main.yml <<'DQ_ASSET'
- ansible.builtin.file:
    mode: '0755'
    path: /srv/routes
    state: directory
  name: Create the route folder
DQ_ASSET
cat > roles/banner/tasks/main.yml <<'DQ_ASSET'
- ansible.builtin.copy:
    content: 'north-ready

      '
    dest: /srv/routes/current
    mode: '0644'
  name: Deliver role banner
DQ_ASSET
cat > roles/banner/meta/main.yml <<'DQ_ASSET'
dependencies: []
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- gather_facts: false
  hosts: fleet
  roles:
  - banner
DQ_ASSET
