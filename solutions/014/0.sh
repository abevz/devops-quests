set -euo pipefail
cd ~/quest
cat > diagnosis.txt <<'DQ_ASSET'
route must equal north
DQ_ASSET
kubectl patch configmap route --type merge -p '{"data":{"name":"north"}}'
kubectl rollout restart deploy/route-worker
kubectl rollout status deployment/route-worker --timeout=60s
