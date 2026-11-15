set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
helm status board -o json | jq -e '.info.status=="deployed"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
helm get values board --all -o json | jq -e '(.port|tostring)=="8080"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/relay --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail
)
[ $? -eq 0 ] || failed=1
exit "$failed"
