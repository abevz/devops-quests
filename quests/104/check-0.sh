set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
cron=$(kubectl get cronjob route-audit -o json 2>/dev/null || true)
valid_schedule() {
python3 -I - /dev/fd/3 3<<<"$1" <<'DQ_CRON'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import re,sys

def field(text,low,high,names=None):
    values=set();wildcard=False
    if names:
        def named(match):
            value=names.get(match.group().lower())
            if value is None:raise ValueError('name')
            return str(value)
        text=re.sub(r'[A-Za-z]+',named,text)
    for part in text.split(','):
        match=re.fullmatch(r'(\*|\?|[0-9]+(?:-[0-9]+)?)(?:/([0-9]+))?',part)
        if not match:raise ValueError('field')
        term,step=match.groups();stride=int(step or 1)
        if stride<1:raise ValueError('step')
        if term in ('*','?'):
            start,end=low,high;wildcard=wildcard or stride==1
        elif '-' in term:start,end=map(int,term.split('-'))
        else:start=int(term);end=high if step else start
        if not low<=start<=end<=high:raise ValueError('range')
        values.update(range(start,end+1,stride))
    return values==set(range(low,high+1)),wildcard
try:
    parts=sys.argv[1].split()
    if len(parts)!=5:raise ValueError('five fields')
    minute,_=field(parts[0],0,59);hour,_=field(parts[1],0,23)
    dom,dom_star=field(parts[2],1,31)
    month,_=field(parts[3],1,12,dict(zip('jan feb mar apr may jun jul aug sep oct nov dec'.split(),range(1,13))))
    dow,dow_star=field(parts[4],0,6,dict(zip('sun mon tue wed thu fri sat'.split(),range(7))))
    # Standard cron combines restricted day fields with OR, wildcard day fields with AND.
    days=(dom and dow) if dom_star or dow_star else (dom or dow)
    ok=minute and hour and month and days
except (ValueError,TypeError):ok=False
sys.exit(not ok)
DQ_CRON
}
field=suspend
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! { if test "$field" = schedule; then
      valid_schedule "$(jq -r '.spec.schedule // ""' <<<"$cron" 2>/dev/null)"
    else jq -e "$expression" <<<"$cron" >/dev/null 2>&1; fi; }; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
field=schedule
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! { if test "$field" = schedule; then
      valid_schedule "$(jq -r '.spec.schedule // ""' <<<"$cron" 2>/dev/null)"
    else jq -e "$expression" <<<"$cron" >/dev/null 2>&1; fi; }; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
field=timeZone
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! { if test "$field" = schedule; then
      valid_schedule "$(jq -r '.spec.schedule // ""' <<<"$cron" 2>/dev/null)"
    else jq -e "$expression" <<<"$cron" >/dev/null 2>&1; fi; }; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
field=concurrencyPolicy
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! { if test "$field" = schedule; then
      valid_schedule "$(jq -r '.spec.schedule // ""' <<<"$cron" 2>/dev/null)"
    else jq -e "$expression" <<<"$cron" >/dev/null 2>&1; fi; }; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
field=startingDeadlineSeconds
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! { if test "$field" = schedule; then
      valid_schedule "$(jq -r '.spec.schedule // ""' <<<"$cron" 2>/dev/null)"
    else jq -e "$expression" <<<"$cron" >/dev/null 2>&1; fi; }; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
cron=$(kubectl get cronjob route-audit -o json 2>/dev/null || true)
field=successfulJobsHistoryLimit
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! jq -e "$expression" <<<"$cron" >/dev/null 2>&1; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
field=failedJobsHistoryLimit
  case "$field" in
    suspend) expression='.spec.suspend==false'; expected=false ;;
    schedule) expression='.spec.schedule=="* * * * *"'; expected='* * * * *' ;;
    timeZone) expression='.spec.timeZone=="Etc/UTC"'; expected=Etc/UTC ;;
    concurrencyPolicy) expression='.spec.concurrencyPolicy=="Forbid"'; expected=Forbid ;;
    startingDeadlineSeconds) expression='.spec.startingDeadlineSeconds==20'; expected=20 ;;
    successfulJobsHistoryLimit|failedJobsHistoryLimit) expression=".spec.$field==1"; expected=1 ;;
  esac
  if ! jq -e "$expression" <<<"$cron" >/dev/null 2>&1; then
    printf '%s\n' "cronjob/route-audit $field = $expected: ✗ [DQ:field_${field,,}]"; failed=1
  fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
cron=$(kubectl get cronjob route-audit -o json 2>/dev/null || true)
uid=$(jq -r '.metadata.uid // ""' <<<"$cron" 2>/dev/null || true)
scheduled=$(jq -r '.status.lastScheduleTime // ""' <<<"$cron" 2>/dev/null || true)
jobs=$(kubectl get jobs -o json 2>/dev/null || true)
owned=$(jq -c --arg uid "$uid" '[.items[]?|select(any(.metadata.ownerReferences[]?;.kind=="CronJob" and .uid==$uid and .controller==true))]' <<<"$jobs" 2>/dev/null || echo '[]')
latest=$(jq -c --arg at "$scheduled" '[.[]|select(.metadata.annotations["batch.kubernetes.io/cronjob-scheduled-timestamp"]==$at)]' <<<"$owned" 2>/dev/null || echo '[]')
job=$(jq -r '[.[]|select(.status.succeeded==1)][0].metadata.name // ""' <<<"$latest" 2>/dev/null || true)
if ! test -n "$scheduled"; then
  printf '%s\n' 'cronjob/route-audit lastScheduleTime: ✗ [DQ:last_time]'; failed=1
fi
if ! test -n "$uid" || ! jq -e 'length>0' <<<"$owned" >/dev/null 2>&1; then printf '%s\n' 'Job owned by cronjob/route-audit: ✗ [DQ:owned]'; failed=1; fi
if ! test -n "$scheduled" || ! jq -e 'length>0' <<<"$latest" >/dev/null 2>&1; then printf '%s\n' 'latest CronJob run has a controller-owned Job: ✗ [DQ:scheduled]'; failed=1; fi
if ! test -n "$job"; then printf '%s\n' 'latest scheduled Job succeeded = 1: ✗ [DQ:succeeded]'; failed=1; fi
if ! test -n "$job" || ! test "$(kubectl logs "job/$job" 2>/dev/null)" = north-104; then
  printf '%s\n' 'latest scheduled Job logs = north-104: ✗ [DQ:logs]'; failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
