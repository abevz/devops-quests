set -euo pipefail
cd ~/quest
failed=0
if ! bash -euo pipefail <<'DQ_LEGACY'
set -euo pipefail
cd ~/quest
failed=0
if ! kubectl rollout status deployment/relay --timeout=3s >/dev/null 2>&1; then
  printf '%s\n' 'deployment/relay rollout complete: ✗ [DQ:rollout]'; failed=1
fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/relay -c worker -- printenv RELEASE 2>/dev/null)" = release-90; then
  printf '%s\n' 'deployment/relay RELEASE = release-90: ✗ [DQ:relay]'; failed=1
fi
exit "$failed"
DQ_LEGACY
then failed=1; fi
expected=$(cat /run/dq/facts/2/relay-handover-id 2>/dev/null || true)
uid=$(cat /run/dq/facts/2/relay-publication-uid 2>/dev/null || true)
publication=$(kubectl --request-timeout=3s get configmap relay-recovery -o json 2>/dev/null || true)
deployment=$(kubectl --request-timeout=3s get deployment relay -o json 2>/dev/null || true)
if ! test -n "$expected" || ! test -n "$uid" ||
   ! jq -e --arg id "$expected" --arg uid "$uid" '.metadata.uid==$uid and .data["recovery-id"]==$id' <<<"$publication" >/dev/null 2>&1 ||
   ! jq -e '.spec.template.spec as $pod |
      any($pod.volumes[]?; .configMap.name=="relay-recovery" and
        (.name as $volume | any($pod.containers[]?; .name=="worker" and
          any(.volumeMounts[]?; .name==$volume and .mountPath=="/run/recovery" and .readOnly==true))))' <<<"$deployment" >/dev/null 2>&1; then
  printf '%s\n' 'Relay publication must project the recovered identity from its original ConfigMap: ✗ [DQ:relay_publication]'
  failed=1
else
  observed=$(timeout 5s kubectl exec --pod-running-timeout=2s deployment/relay -c worker -- sh -ec '
    test "$(cat /proc/1/comm)" = httpd
    test "$(readlink /proc/1/cwd)" = /tmp/www
    test /tmp/www/recovery-id -ef /run/recovery/recovery-id
    projected=$(cat /run/recovery/recovery-id)
    response=$(wget -qO- -T 2 http://127.0.0.1:8080/recovery-id)
    printf "%s\n%s\n" "$projected" "$response"
  ' 2>/dev/null || true)
  if ! test "$observed" = "$(printf '%s\n%s' "$expected" "$expected")"; then
    printf '%s\n' 'Relay worker does not serve its projected recovery identity: ✗ [DQ:relay_identity]'
    failed=1
  fi
fi
exit "$failed"
