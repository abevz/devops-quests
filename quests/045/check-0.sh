set -euo pipefail
cd ~/quest
failed=0
if ! (
kubectl get pvc route-data -o json | jq -e --arg uid "$(cat original-pvc-uid)" '.metadata.uid==$uid and .status.phase=="Bound"' >/dev/null
); then failed=1; fi
if ! (
kubectl get deployment reader -o json | jq -e '.spec.template.spec.volumes==[{"name":"data","persistentVolumeClaim":{"claimName":"route-data"}}] and .spec.template.spec.containers[0].volumeMounts==[{"name":"data","mountPath":"/data","readOnly":true}]' >/dev/null
); then failed=1; fi
if ! (
kubectl rollout status deployment/reader --timeout=3s >/dev/null
); then failed=1; fi
if ! (
test "$(kubectl exec deployment/reader -- cat /data/route.txt)" = north-45
); then failed=1; fi
exit "$failed"
