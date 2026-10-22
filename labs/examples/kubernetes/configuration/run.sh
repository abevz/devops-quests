#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo 'Use the Lab cluster'; exit 1;; esac
kubectl create namespace lab-configuration --dry-run=client -o yaml | kubectl apply -f -
python3 - <<'MANIFEST'
import os,pathlib
s=pathlib.Path('objects.yaml.in').read_text().replace('$DQ_APP_IMAGE',os.environ['DQ_APP_IMAGE'])
pathlib.Path('objects.yaml').write_text(s)
MANIFEST
kubectl -n lab-configuration apply -f objects.yaml
