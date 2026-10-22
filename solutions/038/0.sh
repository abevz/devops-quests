set -euo pipefail
cd ~/quest
mkdir -p group_vars
cat > group_vars/fleet.yml <<'DQ_ASSET'
route: north
DQ_ASSET
ansible-playbook rollout.yml
