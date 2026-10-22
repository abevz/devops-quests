#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for file in case-*/main.tf; do (cd "$(dirname "$file")"; TF_VAR_name=worker-a tofu destroy -auto-approve -input=false); done
