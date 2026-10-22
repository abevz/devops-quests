#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu plan -var=release_value=v2 -out=replace.tfplan
tofu show -json replace.tfplan > plan.json
python3 -c 'import json; p=json.load(open("plan.json")); assert p["resource_changes"][0]["change"]["actions"]==["create","delete"]'
tofu apply -input=false replace.tfplan
[ "$(cat before.out)" != "$(tofu output -raw id)" ]
