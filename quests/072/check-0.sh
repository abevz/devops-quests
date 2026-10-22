set -euo pipefail
cd ~/quest
test "$(kubectl get job importer -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-job-uid)"
kubectl get job importer -o json | jq -e '.spec.backoffLimit==1 and .spec.activeDeadlineSeconds==30 and .spec.parallelism==1 and .spec.template.spec.restartPolicy=="Never" and .status.failed>=1 and .status.failed<=3 and any(.status.conditions[]?;.type=="Failed" and .status=="True" and (.reason=="BackoffLimitExceeded" or .reason=="DeadlineExceeded"))' >/dev/null
kubectl get pods -l job-name=importer -o json | jq -e 'any(.items[];.status.phase=="Failed" and any(.status.containerStatuses[]?;.state.terminated.exitCode==1))' >/dev/null
