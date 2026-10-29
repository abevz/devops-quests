set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
quota=$(timeout 2s kubectl get resourcequota station -o json 2>/dev/null || true)
limits=$(timeout 2s kubectl get limitrange defaults -o json 2>/dev/null || true)
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
pods=$(timeout 2s kubectl get pods -l app=board -o json 2>/dev/null || true)
check quota 'ResourceQuota station hard = supplied budget' '.spec.hard=={"requests.cpu":"200m","limits.cpu":"400m","requests.memory":"32Mi","limits.memory":"64Mi",pods:"2"}' "$quota"
check default 'LimitRange defaults default.cpu = 200m' '.spec.limits[0].default.cpu=="200m"' "$limits"
check request 'LimitRange defaults defaultRequest.cpu = 100m' '.spec.limits[0].defaultRequest.cpu=="100m"' "$limits"
check ready 'deployment board readyReplicas = 1' '.status.readyReplicas==1' "$board"
check template 'board first container resources = empty' '(.spec.template.spec.containers[0].resources//{})=={}' "$board"
check pod_requests 'non-terminating board Pod requests = CPU 100m, memory 16Mi' 'any(.items[]?;.metadata.deletionTimestamp==null and .spec.containers[0].resources.requests=={cpu:"100m",memory:"16Mi"})' "$pods"
check pod_limits 'non-terminating board Pod limits = CPU 200m, memory 32Mi' 'any(.items[]?;.metadata.deletionTimestamp==null and .spec.containers[0].resources.limits=={cpu:"200m",memory:"32Mi"})' "$pods"
check pod_ready 'non-terminating board Pod has a ready container' 'any(.items[]?;.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true))' "$pods"
check same_pod 'one non-terminating Pod has required resources and ready container' 'any(.items[]?;.metadata.deletionTimestamp==null and .spec.containers[0].resources.requests=={cpu:"100m",memory:"16Mi"} and .spec.containers[0].resources.limits=={cpu:"200m",memory:"32Mi"} and any(.status.containerStatuses[]?;.ready==true))' "$pods"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-126; then printf '%s\n' 'board:8080 = north-126: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
