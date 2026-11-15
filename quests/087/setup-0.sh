#!/bin/bash
set -euo pipefail
# The trusted, run-scoped native fixture seeds the concurrent incident before setup.
test -s main.tf
test -s errored.tfstate
test -s failed-apply.log
curl -fsS http://127.0.0.1:18787/owner | python3 -c 'import json,sys; v=json.load(sys.stdin); assert v["registered"] and v["running"]'
