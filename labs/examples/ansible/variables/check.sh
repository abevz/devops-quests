#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml -e message=cli -e expected=cli | tee override.log
grep -q '"message": "cli"' override.log
