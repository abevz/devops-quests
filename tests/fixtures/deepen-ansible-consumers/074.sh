set -euo pipefail
cd ~/quest
ansible-playbook --check --diff rollout.yml > check.log
ansible-playbook rollout.yml > apply.log
