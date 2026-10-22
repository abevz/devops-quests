#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export ANSIBLE_CONFIG="$HOME/lab/ansible.cfg"
ap() { ansible-playbook -i "$HOME/lab/inventory.ini" "$@"; }
head -1 secret.yaml | grep '\$ANSIBLE_VAULT'
! grep -q demo-only-value secret.yaml
! grep -q demo-only-value run.log
if ap playbook.yaml > missing-key.log 2>&1; then echo 'Expected decryption failure'; exit 1; fi
ansible-vault view secret.yaml --vault-password-file .vault-password | grep -q demo-only-value
