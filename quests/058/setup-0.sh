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

mkdir -p roles/banner/defaults roles/base/meta
cat > roles/banner/defaults/main.yml <<'DQ_DEFAULTS'
install_root: /srv/routes
banner_route: north-ready
DQ_DEFAULTS
cat > roles/base/meta/main.yml <<'DQ_META'
allow_duplicates: false
DQ_META
cat > role-contract.json <<'DQ_CONTRACT'
{
  "schema": 1,
  "entryRole": "roles/banner",
  "inputs": {
    "install_root": "caller-owned output directory",
    "banner_route": "caller route text"
  },
  "output": "current file below install_root",
  "cases": {
    "first": "south-ready",
    "second": "east-ready"
  },
  "multipleCallsInOnePlay": true,
  "preserveOtherCallerData": true,
  "secondApplicationNoChanges": true,
  "localUnprivilegedCaller": true,
  "preserveDefaultFleetResult": true,
  "observesCurrentProgramCapabilityOnly": true
}
DQ_CONTRACT
