#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CLEAN'
import pathlib,subprocess
for folder in pathlib.Path('.').glob('case-*'):
 p=folder/'main.tf';s=p.read_text();p.write_text(s.replace('prevent_destroy = true','prevent_destroy = false'))
 try:subprocess.run(['tofu','destroy','-auto-approve','-input=false'],cwd=folder,check=True,stdout=subprocess.DEVNULL)
 finally:p.write_text(s)
CLEAN
