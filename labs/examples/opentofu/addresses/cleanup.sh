#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu destroy -auto-approve -input=false
rm -f ./*.tfplan ./*.log ./*.json
test ! -f original.tf.example || cp original.tf.example main.tf
