#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-placement
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
k wait --for=condition=PodScheduled=false pod/toobig --timeout=30s
k rollout status deployment/spread --timeout=90s
k wait --for=condition=Ready pod/important --timeout=90s
[ "$(k get pod placed -o jsonpath='{.spec.nodeName}')" = "$worker" ]
[ "$(k get pod important -o jsonpath='{.spec.preemptionPolicy}')" = Never ]
k get pods -l app=spread -o json > spread.json
python3 - <<'CHECK'
import json,collections
counts=collections.Counter(p['spec']['nodeName'] for p in json.load(open('spread.json'))['items'])
assert sum(counts.values())==3 and len(counts)==2 and max(counts.values())-min(counts.values())<=1
print('Toleration, node selection, spread and non-preempting priority verified.')
CHECK
