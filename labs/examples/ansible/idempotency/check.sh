#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml | tee second.log
grep -q "changed=0" second.log
ap playbook.yaml --check --diff | tee check.log
grep -q "changed=0" check.log
