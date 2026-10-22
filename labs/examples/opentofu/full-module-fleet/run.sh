#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for file in case-*/main.tf; do
 (cd "$(dirname "$file")"; tofu init -input=false; tofu validate; tofu apply -auto-approve -input=false ; tofu state list > addresses.out)
done
