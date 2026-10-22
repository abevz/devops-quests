set -euo pipefail
cd ~/quest
source platform.env
git -C repository revert --no-edit "$(cat /run/dq/facts/0/faulty-commit)"
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
