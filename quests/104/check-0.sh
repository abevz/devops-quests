set -euo pipefail
cd ~/quest
kubectl get cronjob route-audit -o json | jq -e '.spec.suspend==false and .spec.schedule=="* * * * *" and .spec.timeZone=="Etc/UTC" and .spec.concurrencyPolicy=="Forbid" and .status.lastScheduleTime!=null' >/dev/null
uid=$(kubectl get cronjob route-audit -o jsonpath='{.metadata.uid}')
scheduled=$(kubectl get cronjob route-audit -o jsonpath='{.status.lastScheduleTime}')
job=$(kubectl get jobs -o json | jq -er --arg uid "$uid" --arg at "$scheduled" '[.items[]|select(any(.metadata.ownerReferences[]?;.kind=="CronJob" and .uid==$uid and .controller==true))|select(.metadata.annotations["batch.kubernetes.io/cronjob-scheduled-timestamp"]==$at)|select(.status.succeeded==1)][0].metadata.name')
test "$job" != null
test "$(kubectl logs job/"$job")" = north-104
