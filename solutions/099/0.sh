set -euo pipefail
cd ~/quest
source platform.env
umask 077
cat > issue.json <<'ISSUE'
{"policies":["rail-reader"],"ttl":"300s","renewable":false,"explicit_max_ttl":"600s"}
ISSUE
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @issue.json "$VAULT_ADDR/v1/auth/token/create/rail-rotation" | jq -er .auth.client_token > station-token
jq -n --arg accessor "$(cat /run/dq/facts/0/compromised-accessor)" '{accessor:$accessor}' > revoke.json
curl -fsS -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @revoke.json "$VAULT_ADDR/v1/auth/token/revoke-accessor"
bash sync-secret.sh
source platform.env
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD" --dry-run=client -o json | kubectl apply -f -
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
kubectl rollout status deployment/board --timeout=60s
