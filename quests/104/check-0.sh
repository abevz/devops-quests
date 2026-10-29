set -euo pipefail
cd ~/quest
failed=0
cron=$(kubectl get cronjob route-audit -o json 2>/dev/null || true)
for field in suspend schedule timeZone concurrencyPolicy startingDeadlineSeconds successfulJobsHistoryLimit failedJobsHistoryLimit; do
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! jq -e "$expression" <<<"$cron" >/dev/null 2>&1; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗"; failed=1
  fi
done
uid=$(jq -r '.metadata.uid // ""' <<<"$cron" 2>/dev/null || true)
scheduled=$(jq -r '.status.lastScheduleTime // ""' <<<"$cron" 2>/dev/null || true)
if ! test -n "$scheduled"; then
  printf '%s\n' 'cronjob/route-audit lastScheduleTime: ✗'; failed=1
fi
jobs=$(kubectl get jobs -o json 2>/dev/null || true)
owned=$(jq -c --arg uid "$uid" '[.items[]?|select(any(.metadata.ownerReferences[]?;.kind=="CronJob" and .uid==$uid and .controller==true))]' <<<"$jobs" 2>/dev/null || echo '[]')
if ! test -n "$uid" || ! jq -e 'length>0' <<<"$owned" >/dev/null 2>&1; then printf '%s\n' 'Job owned by cronjob/route-audit: ✗'; failed=1; fi
latest=$(jq -c --arg at "$scheduled" '[.[]|select(.metadata.annotations["batch.kubernetes.io/cronjob-scheduled-timestamp"]==$at)]' <<<"$owned" 2>/dev/null || echo '[]')
if ! test -n "$scheduled" || ! jq -e 'length>0' <<<"$latest" >/dev/null 2>&1; then printf '%s\n' 'owned Job scheduled timestamp = lastScheduleTime: ✗'; failed=1; fi
job=$(jq -r '[.[]|select(.status.succeeded==1)][0].metadata.name // ""' <<<"$latest" 2>/dev/null || true)
if ! test -n "$job"; then printf '%s\n' 'latest scheduled Job succeeded = 1: ✗'; failed=1; fi
if ! test -n "$job" || ! test "$(kubectl logs "job/$job" 2>/dev/null)" = north-104; then
  printf '%s\n' 'latest scheduled Job logs = north-104: ✗'; failed=1
fi
exit "$failed"
