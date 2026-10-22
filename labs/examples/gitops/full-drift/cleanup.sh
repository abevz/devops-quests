#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
source "$HOME/lab/platform.env"
app=lab-guide
state() { kubectl -n "$LAB_NAMESPACE" get application "$app" -o json | jq '{sync:.status.sync.status,health:.status.health.status,operation:.status.operationState.phase}'; }
refresh() { kubectl -n "$LAB_NAMESPACE" annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite; }
sync() {
 kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"operation":{"sync":{"prune":true}}}'
 kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.operationState.phase}'=Succeeded application/"$app" --timeout=150s
}
kubectl -n "$LAB_NAMESPACE" delete application "$app" --ignore-not-found --wait=true
kubectl -n "$LAB_NAMESPACE" delete job/lab-preflight configmap/lab-settings deployment/lab-web service/lab-web --ignore-not-found --wait=true
kubectl -n "$LAB_NAMESPACE" delete configmap lab-field-owner --ignore-not-found
