#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cp main.tf original.tf.example
cp renamed.tf.example main.tf
tofu plan -out=move.tfplan
tofu show -json move.tfplan > plan.json
python3 -c 'import json; p=json.load(open("plan.json")); c=p["resource_changes"][0]; assert c["previous_address"]=="terraform_data.old" and c["change"]["actions"]==["no-op"]'
tofu apply -input=false move.tfplan
[ "$(cat before.out)" = "$(tofu output -raw id)" ]
tofu state list | grep -qx terraform_data.new
