#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
[ "$(kubectl -n lab-helm get cm demo-settings -o jsonpath='{.data.message}')" = second ]
helm rollback demo 1 -n lab-helm --wait --timeout=90s
[ "$(kubectl -n lab-helm get cm demo-settings -o jsonpath='{.data.message}')" = first ]
helm history demo -n lab-helm -o json | python3 -c 'import json,sys; h=json.load(sys.stdin); assert h[-1]["revision"]==3 and h[-1]["status"]=="deployed"'
if helm upgrade demo ./chart -n lab-helm --set-string image=lab-missing:never --rollback-on-failure --timeout=20s > failure.log 2>&1; then echo 'Expected failed upgrade'; exit 1; fi
helm status demo -n lab-helm -o json | python3 -c 'import json,sys; assert json.load(sys.stdin)["info"]["status"]=="deployed"'
kubectl -n lab-helm rollout status deployment/demo --timeout=90s
[ "$(kubectl -n lab-helm get deployment demo -o jsonpath='{.spec.template.spec.containers[0].image}')" = "$DQ_APP_IMAGE" ]
echo 'Rollback created a new revision; failed upgrade restored the last deployed workload.'
