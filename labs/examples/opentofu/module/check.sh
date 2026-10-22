#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[ "$(tofu output -raw name)" = api ]
tofu state list | grep 'module.api.terraform_data.this'
