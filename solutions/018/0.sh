set -euo pipefail
cd ~/quest
cat > board.j2 <<'DQ_ASSET'
station={{ inventory_hostname }} route={{ route }} slots={{ slots }}
DQ_ASSET
ansible-playbook rollout.yml
