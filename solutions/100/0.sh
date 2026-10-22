set -euo pipefail
cd ~/quest
kubectl patch application board --type=merge -p '{"spec":{"source":{"path":"manifests"}}}'
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 60); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null; then break; fi
 sleep 1
done
