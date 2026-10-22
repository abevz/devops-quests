#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for file in inventory-*.yaml inventory-*.ini; do
  ansible-inventory -i "$file" --list > "$file.json"
done
ansible-playbook -i inventory-1.yaml ping.yml --limit localhost > result.log
