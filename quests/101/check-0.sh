set -euo pipefail
cd ~/quest
failed=0
board=$(kubectl get deployment board -o json 2>/dev/null || true)
pods=$(kubectl get pods -l app=board -o json 2>/dev/null || true)
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
check 'watcher startup command = test -s /shared/heartbeat [DQ:startup_command]' '.spec.template.spec.initContainers[1].startupProbe.exec.command==["test","-s","/shared/heartbeat"]' "$board"
check 'watcher startup periodSeconds = 1 [DQ:period]' '.spec.template.spec.initContainers[1].startupProbe.periodSeconds==1' "$board"
check 'watcher startup failureThreshold = 10 [DQ:threshold]' '.spec.template.spec.initContainers[1].startupProbe.failureThreshold==10' "$board"
check 'prepare command = sh -c cp /input/route /shared/route [DQ:prepare]' '.spec.template.spec.initContainers[0].command==["sh","-c","cp /input/route /shared/route"]' "$board"
check 'watcher restartPolicy = Always [DQ:restart]' '.spec.template.spec.initContainers[1].restartPolicy=="Always"' "$board"
check 'board volumes = supplied input and shared volumes [DQ:volumes]' '.spec.template.spec.volumes==[{name:"input",configMap:{name:"route",defaultMode:420}},{name:"shared",emptyDir:{}}]' "$board"
check 'a nonterminating board Pod has successful prepare [DQ:prepare_status]' 'any(.items[]?;.metadata.deletionTimestamp==null and any(.status.initContainerStatuses[]?;.name=="prepare" and .state.terminated.exitCode==0))' "$pods"
check 'a nonterminating board Pod has started running watcher [DQ:watcher_status]' 'any(.items[]?;.metadata.deletionTimestamp==null and any(.status.initContainerStatuses[]?;.name=="watcher" and .started==true and .state.running!=null))' "$pods"
check 'a nonterminating board Pod has a ready regular container [DQ:ready]' 'any(.items[]?;.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true))' "$pods"
check 'one nonterminating board Pod has all three conditions [DQ:same]' 'any(.items[]?;.metadata.deletionTimestamp==null and any(.status.initContainerStatuses[]?;.name=="prepare" and .state.terminated.exitCode==0) and any(.status.initContainerStatuses[]?;.name=="watcher" and .started==true and .state.running!=null) and any(.status.containerStatuses[]?;.ready==true))' "$pods"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080/route 2>/dev/null)" = north-101; then printf '%s\n' 'board:8080/route = north-101: ✗ [DQ:http]'; failed=1; fi
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c watcher -- test -s /shared/heartbeat >/dev/null 2>&1; then printf '%s\n' 'watcher /shared/heartbeat is nonempty: ✗ [DQ:heartbeat]'; failed=1; fi
exit "$failed"
