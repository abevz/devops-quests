#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import json
x=json.load(open("results.json")); assert x and all(r["passed"] for r in x); print(len(x),"source configurations and transitions passed")
CHECK
