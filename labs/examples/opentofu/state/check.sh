#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
printf 'external edit
' > managed.txt
set +e
tofu plan -detailed-exitcode -out=drift.tfplan > drift.log
code=$?
set -e
[ "$code" = 2 ]
tofu show drift.tfplan
tofu apply -input=false drift.tfplan
[ "$(cat managed.txt)" = declared ]
tofu state pull > state.json
python3 -c 'import json; s=json.load(open("state.json")); assert s["lineage"] and s["serial"] > 0'
