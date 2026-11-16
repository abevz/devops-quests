set -euo pipefail
cd ~/quest
source platform.env
kubectl -n "$ARGO_NAMESPACE" patch secret station-repository --type=merge -p "$(jq -n --arg password "$GIT_PASSWORD" '{stringData:{password:$password}}')"
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
