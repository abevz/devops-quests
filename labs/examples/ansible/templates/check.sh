#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ap playbook.yaml | tee repeat.log
grep -q "changed=0" repeat.log
ap playbook.yaml -e listen_port=9090 | tee changed.log
grep -q "port=9090" changed.log
