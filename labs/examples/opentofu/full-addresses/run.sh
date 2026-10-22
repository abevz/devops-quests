#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cp stage-2.tf.example main.tf
tofu init -input=false
tofu apply -auto-approve -input=false
tofu state pull > before.json
cp stage-5.tf.example main.tf
tofu init -input=false
tofu apply -auto-approve -input=false
tofu state pull > moved.json
cp stage-7.tf.example main.tf
tofu init -input=false
tofu plan -out=broken.tfplan
tofu show -json broken.tfplan > broken.json
cp stage-9.tf.example main.tf
tofu apply -auto-approve -input=false
tofu state pull > renamed.json
cp stage-11.tf.example main.tf
tofu apply -auto-approve -input=false
tofu state list > forgotten.out
cp stage-13.tf.example main.tf
if tofu validate > unsupported.log 2>&1; then echo 'Expected keyed removed rejection'; exit 1; fi
cp stage-11.tf.example main.tf
