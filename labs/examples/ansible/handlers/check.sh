#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
[ "$(grep -c 'RUNNING HANDLER.*apply configuration' first.log)" = 1 ]
ap playbook.yaml | tee repeat.log
! grep -q 'RUNNING HANDLER' repeat.log
grep -q "changed=0" repeat.log
