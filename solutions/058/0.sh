set -euo pipefail
cd ~/quest
cat > roles/banner/meta/main.yml <<'DQ_ASSET'
dependencies:
  - base
DQ_ASSET
cat > rollout.yml <<'DQ_ASSET'
- gather_facts: false
  hosts: fleet
  roles:
  - banner
DQ_ASSET
ansible-playbook rollout.yml
