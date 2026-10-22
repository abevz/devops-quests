#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml --limit app2 | tee limited.log
grep -q "app2.*ok=2" limited.log
! grep -q "app1.*ok=" limited.log
