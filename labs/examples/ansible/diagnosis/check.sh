#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
grep -qi undefined undefined.log
ap playbook.yaml -e required_message=fixed | tee fixed.log
if ap assert.yaml > assertion.log 2>&1; then echo "Expected assertion failure"; exit 1; fi
grep -q "failed=1" assertion.log
echo "Valid syntax did not prove runtime inputs or assertions."
