set -euo pipefail
cd ~/quest
kubectl get daemonset relay -o json | jq -e '.spec.template.spec | .hostNetwork!=true and .hostPID!=true and .hostIPC!=true and all(.volumes[]?; .hostPath==null) and .securityContext.runAsNonRoot==true and .securityContext.seccompProfile.type=="RuntimeDefault" and all((.containers+(.initContainers//[]))[]; .securityContext.privileged!=true and .securityContext.allowPrivilegeEscalation==false and .securityContext.capabilities.drop==["ALL"])' >/dev/null
kubectl get daemonset relay -o json | jq -e '.spec.template.spec.nodeSelector=={"kubernetes.io/os":"linux"} and .status.desiredNumberScheduled==1 and .status.numberReady==1 and .status.numberAvailable==1' >/dev/null
uid=$(kubectl get daemonset relay -o jsonpath='{.metadata.uid}')
kubectl get pods -l app=relay -o json | jq -e --arg node "$DQ_NODE_NAME" --arg uid "$uid" 'any(.items[];.metadata.deletionTimestamp==null and .spec.nodeName==$node and any(.metadata.ownerReferences[]?;.kind=="DaemonSet" and .uid==$uid and .controller==true) and any(.status.containerStatuses[]?;.ready==true))' >/dev/null
test "$(kubectl exec daemonset/relay -- wget -qO- -T 3 http://relay:8080)" = north-103
