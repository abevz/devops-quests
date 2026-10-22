#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu init -input=false
tofu apply -auto-approve -input=false
