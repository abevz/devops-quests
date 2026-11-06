set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
kubectl get pvc route-data -o json | jq -e --arg uid "$(cat original-pvc-uid)" '.metadata.uid==$uid and .status.phase=="Bound"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl get deployment reader -o json | jq -e '.spec.template.spec.volumes==[{"name":"data","persistentVolumeClaim":{"claimName":"route-data"}}] and .spec.template.spec.containers[0].volumeMounts==[{"name":"data","mountPath":"/data","readOnly":true}]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/reader --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/reader -- cat /data/route.txt)" = north-45
)
[ $? -eq 0 ] || failed=1
exit "$failed"
