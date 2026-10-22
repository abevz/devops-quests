#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
helm status demo -n lab-helm-full -o json > status.json
python3 - <<'CHECK'
import json
x=json.load(open('status.json'));assert x['info']['status']=='deployed' and x['version']>=3
CHECK
kubectl -n lab-helm-full rollout status deployment/demo --timeout=90s
[ "$(kubectl -n lab-helm-full get deployment demo -o jsonpath='{.spec.template.spec.containers[0].image}')" = "$DQ_APP_IMAGE" ]
[ "$(kubectl -n lab-helm-full exec deployment/demo -- cat /data/schema)" = schema-v2 ]
echo 'The workload rolled back; the hook-written PVC data stayed at schema-v2. This is a data-side-effect simulation, not a database engine.'
