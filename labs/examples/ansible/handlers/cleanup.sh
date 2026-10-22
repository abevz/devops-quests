#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
ansible -i "$HOME/lab/inventory.ini" app1 -m ansible.builtin.shell -a "rm -f /tmp/lab-handler-a /tmp/lab-handler-b"
rm -f ./*.log
