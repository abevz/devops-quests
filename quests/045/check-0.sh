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
kubectl get deployment reader -o json | jq -e '.spec.template.spec as $pod | [$pod.containers[]? | select(.name=="worker")] as $workers | ($workers|length)==1 and ($pod.volumes|length)==1 and ($pod.volumes[0] as $volume | ($volume.name|type=="string" and length>0) and ($volume|keys-["name","persistentVolumeClaim"]|length)==0 and $volume.persistentVolumeClaim.claimName=="route-data" and ($volume.persistentVolumeClaim|keys-["claimName","readOnly"]|length)==0 and ($volume.persistentVolumeClaim.readOnly==null or $volume.persistentVolumeClaim.readOnly==false or $volume.persistentVolumeClaim.readOnly==true) and ($workers[0].volumeMounts|length)==1 and ([($pod.containers+($pod.initContainers//[]))[] | .volumeMounts[]?]|length)==1 and ($workers[0].volumeMounts[0] | .name==$volume.name and .mountPath=="/data" and (.readOnly==true or $volume.persistentVolumeClaim.readOnly==true) and (.subPath==null or .subPath=="") and (.subPathExpr==null or .subPathExpr=="") and (.mountPropagation==null or .mountPropagation=="None") and (.recursiveReadOnly==null or .recursiveReadOnly=="Disabled") and (keys-["name","mountPath","readOnly","subPath","subPathExpr","mountPropagation","recursiveReadOnly"]|length)==0))' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/reader --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/reader -c worker -- cat /data/route.txt)" = north-45
)
[ $? -eq 0 ] || failed=1
exit "$failed"
