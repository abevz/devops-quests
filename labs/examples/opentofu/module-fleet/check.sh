#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu output -json names | python3 -c 'import json,sys; assert json.load(sys.stdin)=={"api":"api","worker":"worker"}'
tofu state list | tee addresses.out
grep -F 'module.service["api"].terraform_data.this' addresses.out
grep -F 'module.service["worker"].terraform_data.this' addresses.out
