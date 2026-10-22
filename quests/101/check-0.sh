set -euo pipefail
cd ~/quest
kubectl get deployment board -o json | jq -e '.spec.template.spec.initContainers[1].startupProbe | .exec.command==["test","-s","/shared/heartbeat"] and .periodSeconds==1 and .failureThreshold==10' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.template.spec.initContainers[0].command==["sh","-c","cp /input/route /shared/route"] and .spec.template.spec.initContainers[1].restartPolicy=="Always" and .spec.template.spec.volumes==[{name:"input",configMap:{name:"route",defaultMode:420}},{name:"shared",emptyDir:{}}]' >/dev/null
kubectl get pods -l app=board -o json | jq -e 'any(.items[];.metadata.deletionTimestamp==null and any(.status.initContainerStatuses[]?;.name=="prepare" and .state.terminated.exitCode==0) and any(.status.initContainerStatuses[]?;.name=="watcher" and .started==true and .state.running!=null) and any(.status.containerStatuses[]?;.ready==true))' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080/route)" = north-101
kubectl exec deployment/board -c watcher -- test -s /shared/heartbeat
