#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/lab/images.env"
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) exit 1 ;; esac
ns=lab-full-troubleshooting
k() { kubectl -n "$ns" "$@"; }
worker=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.name|endswith("-worker")) | .metadata.name')
python3 prepare.py
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
k apply -f lab-8.yaml
sed "s|REPLACE_WITH_LAB_IMAGE|$DQ_APP_IMAGE|" failures.yaml | k apply -f -
k wait --for=condition=Ready pod/vg-k8s-app --timeout=90s
# Capture a previous crash while that container still exists; kubelet may
# garbage-collect its logs during the longer network/debug experiments below.
for try in $(seq 1 60); do
 k logs vg-k8s-crash -c app --previous > crash.log 2>&1 || true
 k get pod vg-k8s-crash -o json > crash-status.json
 if grep -q '/config/app.yaml' crash.log && jq -e '.status.containerStatuses[0].lastState.terminated.exitCode == 3' crash-status.json >/dev/null; then break; fi
 sleep 1
done
grep -q '/config/app.yaml' crash.log
jq -e '.status.containerStatuses[0].lastState.terminated.exitCode == 3' crash-status.json >/dev/null
k create deployment policy-target --image="$NGINX"
k rollout status deployment/policy-target --timeout=90s
k expose deployment policy-target --port=80
k debug vg-k8s-app --image="$TOOLS" --image-pull-policy=Never --target=app --container=tools --profile=general -- sleep 3600
for try in $(seq 1 40); do
 k get pod vg-k8s-app -o json | jq -e '.status.ephemeralContainerStatuses[]? | select(.name=="tools") | .state.running' >/dev/null && break
 sleep 1
done
k exec vg-k8s-app -c tools -- true
