#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml --tags static | tee static.log
grep -q reusable-task-ran static.log
ap playbook.yaml --tags dynamic | tee dynamic.log
! grep -q '"msg": "reusable-task-ran"' dynamic.log
echo "An include tag selected the include itself, not its untagged child."
