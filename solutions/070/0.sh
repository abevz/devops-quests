set -euo pipefail
cd ~/quest
kubectl patch application board --type=merge -p '{"spec":{"source":{"path":"manifests"}}}'
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e '.status.sync.status=="Synced"' >/dev/null; then break; fi
 sleep 1
done
