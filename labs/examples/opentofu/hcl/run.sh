#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu init -input=false
tofu validate
tofu plan -out=example.tfplan
tofu apply -input=false example.tfplan
