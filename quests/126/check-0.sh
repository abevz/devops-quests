set -euo pipefail
cd ~/quest
kubectl get resourcequota station -o json | jq -e '.spec.hard=={"requests.cpu":"200m","limits.cpu":"400m","requests.memory":"32Mi","limits.memory":"64Mi",pods:"2"}' >/dev/null
kubectl get limitrange defaults -o json | jq -e '.spec.limits[0].default.cpu=="200m" and .spec.limits[0].defaultRequest.cpu=="100m"' >/dev/null
kubectl get deployment board -o json | jq -e '.status.readyReplicas==1 and (.spec.template.spec.containers[0].resources//{})=={}' >/dev/null
kubectl get pods -l app=board -o json | jq -e 'any(.items[];.metadata.deletionTimestamp==null and .spec.containers[0].resources.requests=={cpu:"100m",memory:"16Mi"} and .spec.containers[0].resources.limits=={cpu:"200m",memory:"32Mi"} and any(.status.containerStatuses[]?;.ready==true))' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-126
