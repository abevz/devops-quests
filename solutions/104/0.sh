set -euo pipefail
cd ~/quest
kubectl patch cronjob route-audit --type=merge -p '{"spec":{"suspend":false,"concurrencyPolicy":"Forbid"}}'
for i in $(seq 1 90); do
 if kubectl get cronjob route-audit -o json | jq -e '.status.lastSuccessfulTime!=null' >/dev/null; then break; fi
 sleep 1
done
