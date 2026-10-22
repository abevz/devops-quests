#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
if ap playbook.yaml -e fail_on=app2 > failure.log 2>&1; then echo "Expected batch failure"; exit 1; fi
grep -q "app2.*failed=1" failure.log
! grep -q "begin app3" failure.log
echo "The failed second batch prevented the third host from entering the play."
