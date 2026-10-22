#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu destroy -auto-approve -input=false
rm -f ./*.tfplan ./*.log ./*.json
