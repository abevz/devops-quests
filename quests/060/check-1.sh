set -euo pipefail
cd ~/quest
if ! bash -euo pipefail <<'DQ_LEGACY'
kubectl rollout status deployment/relay --timeout=3s >/dev/null
test "$(kubectl exec deployment/relay -c worker -- printenv RELEASE)" = release-60
DQ_LEGACY
then
  printf '%s\n' 'The relay rollout or running release is incomplete: ✗ [DQ:relay_release]'
  exit 1
fi
expected=$(cat /run/dq/facts/1/fleet-release.txt 2>/dev/null || true)
uid=$(cat /run/dq/facts/1/release-config-uid 2>/dev/null || true)
publication=$(kubectl --request-timeout=3s get configmap relay-release -o json 2>/dev/null || true)
deployment=$(kubectl --request-timeout=3s get deployment relay -o json 2>/dev/null || true)
if ! test "$expected" = release-60 || ! test -n "$uid" ||
   ! jq -e --arg uid "$uid" --arg revision "$expected" '.metadata.uid == $uid and .data.revision == $revision' <<<"$publication" >/dev/null 2>&1 ||
   ! jq -e '[
       .spec.template.spec.containers[]? | select(.name=="worker") | .env[]? | select(.name=="RELEASE")
     ] | length == 1 and .[0].valueFrom.configMapKeyRef.name == "relay-release" and
       .[0].valueFrom.configMapKeyRef.key == "revision" and (.[0].value // "") == ""' <<<"$deployment" >/dev/null 2>&1; then
  printf '%s\n' 'The relay release is not bound to the original fleet publication: ✗ [DQ:release_source]'
  exit 1
fi
