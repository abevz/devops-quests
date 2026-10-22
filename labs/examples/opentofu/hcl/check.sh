#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu output -json active | python3 -c 'import sys,json; assert json.load(sys.stdin)=={"api":"dev/api"}'
if tofu plan -var=environment=production > invalid.log 2>&1; then echo 'Expected validation error'; exit 1; fi
grep -q 'Use dev, test or prod' invalid.log
tofu plan -detailed-exitcode
