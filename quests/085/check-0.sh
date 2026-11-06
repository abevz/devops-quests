set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get pdb relay -o json | jq -e '.spec.minAvailable==1' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pdb relay -o json | jq -e '.status.currentHealthy>=2' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get pdb relay -o json | jq -e '.status.disruptionsAllowed>=1' >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
