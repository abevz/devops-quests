#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
umask 077
printf 'local-training-password
' > .vault-password
printf 'training_secret: demo-only-value
' > secret.yaml
ansible-vault encrypt secret.yaml --vault-password-file .vault-password
ap playbook.yaml --vault-password-file .vault-password | tee run.log
