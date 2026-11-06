set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
jq -e '.=={action:"start"}' registry-repair.json >/dev/null
endpoint=$(jq -er .endpoint /run/dq/facts/0/registry-target.json)
curl -fsS --max-time 3 --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$endpoint/v2/" >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/registry-target.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image and .spec.template.spec.containers[0].imagePullPolicy=="Always" and .spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' >/dev/null
digest=$(printf %s "$image" | cut -d@ -f2)
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[];.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
image=$(jq -er .image /run/dq/facts/0/registry-target.json)
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.replicas==1' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-78
)
[ $? -eq 0 ] || failed=1
exit "$failed"
