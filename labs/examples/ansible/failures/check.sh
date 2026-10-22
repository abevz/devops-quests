#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
grep -q "rescued=1" rescued.log
grep -q always-ran rescued.log
if ap unhandled.yaml > unhandled.log 2>&1; then echo "Expected failure"; exit 1; fi
grep -q "failed=1" unhandled.log
