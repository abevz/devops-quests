set -euo pipefail
cd ~/quest
failed=0
job=$(kubectl get job importer -o json 2>/dev/null || true)
uid=$(cat /run/dq/facts/0/original-job-uid 2>/dev/null || true)
if ! test -n "$uid" || ! jq -e --arg uid "$uid" '.metadata.uid==$uid' <<<"$job" >/dev/null 2>&1; then
  printf '%s\n' 'job/importer UID = /run/dq/facts/0/original-job-uid: ✗'
  failed=1
fi
for field in backoffLimit activeDeadlineSeconds parallelism; do
  case "$field" in backoffLimit|parallelism) expected=1 ;; activeDeadlineSeconds) expected=30 ;; esac
  if ! jq -e --arg field "$field" --argjson expected "$expected" '.spec[$field]==$expected' <<<"$job" >/dev/null 2>&1; then
    printf '%s\n' "job/importer $field = $expected: ✗"
    failed=1
  fi
done
if ! jq -e 'any(.spec.template.spec.containers[]?; .name=="worker" and .command==["sh","-c","echo invalid-route >&2; exit 1"])' <<<"$job" >/dev/null 2>&1; then
  printf '%s\n' 'job/importer worker command = supplied job.json command: ✗'
  failed=1
fi
if ! jq -e '.spec.template.spec.restartPolicy=="Never"' <<<"$job" >/dev/null 2>&1; then
  printf '%s\n' 'job/importer restartPolicy = Never: ✗'
  failed=1
fi
if ! jq -e '(.status.failed // 0)>=1' <<<"$job" >/dev/null 2>&1; then
  printf '%s\n' 'job/importer status.failed >= 1: ✗'
  failed=1
fi
if ! jq -e 'any(.status.conditions[]?; .type=="Failed" and .status=="True")' <<<"$job" >/dev/null 2>&1; then
  printf '%s\n' 'job/importer Failed = True: ✗'
  failed=1
fi
if ! kubectl get pods -l job-name=importer -o json 2>/dev/null | jq -e --arg uid "$uid" 'any(.items[]; .status.phase=="Failed" and any(.metadata.ownerReferences[]?; .kind=="Job" and .uid==$uid and .controller==true) and any(.status.containerStatuses[]?; .name=="worker" and .state.terminated.exitCode==1))' >/dev/null 2>&1; then
  printf '%s\n' 'job/importer owned Failed Pod worker exitCode = 1: ✗'
  failed=1
fi
exit "$failed"
