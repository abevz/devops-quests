#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import json
r=json.load(open("results.json")); assert r and all(c["passed"] for c in r); print(len(r),"full source playbooks passed")
CHECK
