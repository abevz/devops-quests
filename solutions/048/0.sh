set -euo pipefail
cd ~/quest
cat > renew-request.json <<'DQ_ASSET'
{"increment": "180s"}
DQ_ASSET
bash issue-token.sh
bash renew-token.sh
bash sync-secret.sh
kubectl rollout restart deployment/reader
kubectl rollout status deployment/reader --timeout=90s
