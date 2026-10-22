#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml --syntax-check
if ap playbook.yaml > undefined.log 2>&1; then echo "Expected undefined variable"; exit 1; fi
