set -euo pipefail
cd ~/quest
kubectl get deployment board -o json | jq -e '.spec.replicas==1 and .spec.template.spec.securityContext.runAsNonRoot==true and .spec.template.spec.securityContext.runAsUser==1000 and .spec.template.spec.securityContext.seccompProfile.type=="RuntimeDefault" and .spec.template.spec.containers[0].securityContext=={privileged:false,allowPrivilegeEscalation:false,capabilities:{drop:["ALL"]},readOnlyRootFilesystem:true} and .spec.template.spec.volumes==[{name:"scratch",emptyDir:{}}] and .spec.template.spec.containers[0].volumeMounts==[{name:"scratch",mountPath:"/tmp"}] and .status.readyReplicas==1' >/dev/null
if kubectl auth can-i patch namespaces >/dev/null 2>&1; then exit 1; fi
if kubectl exec deployment/board -- touch /read-only-probe >/dev/null 2>&1; then exit 1; fi
kubectl exec deployment/board -- sh -c 'test "$(id -u)" = 1000; printf writable > /tmp/write-probe; test "$(cat /tmp/write-probe)" = writable'
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-109
