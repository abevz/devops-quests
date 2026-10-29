set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
umask 077
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
api=$(cat /run/dq/facts/0/api-endpoint 2>/dev/null || true)
request() {
  local credential=$1 path=$2 output=$3
  if ! [[ "$credential" =~ ^[A-Za-z0-9._-]+$ ]] || ! test -n "$api"; then return 1; fi
  printf 'header = "Authorization: Bearer %s"\n' "$credential" | timeout 2s curl --config - --cacert /run/dq/facts/0/api-ca.pem -sS -o "$output" -w '%{http_code}' "$api/api/v1/namespaces/$DQ_NAMESPACE/$path" 2>/dev/null
}
reader=$(timeout 2s kubectl get deployment reader -o json 2>/dev/null || true)
check 'reader automountServiceAccountToken = false [DQ:automount]' '.spec.template.spec.automountServiceAccountToken==false' "$reader"
check 'reader first projected token = path token, audience and 600 seconds [DQ:projection]' '.spec.template.spec.volumes[0].projected.sources[0].serviceAccountToken=={path:"token",expirationSeconds:600,audience:"https://kubernetes.default.svc.cluster.local"}' "$reader"
role=$(timeout 2s kubectl get role reader -o json 2>/dev/null || true)
check 'role/reader rules = named route get only [DQ:role]' '.rules==[{apiGroups:[""],resources:["configmaps"],resourceNames:["route"],verbs:["get"]}]' "$role"
token=$(timeout 2s kubectl exec --pod-running-timeout=2s deployment/reader -- cat /credential/token 2>/dev/null || true)
status=$(request "$token" configmaps/route "$scratch/route" || true)
if ! test "$status" = 200; then printf '%s\n' 'reader GET configmaps/route status = 200: ✗ [DQ:allowed]'; failed=1; fi
if ! jq -e '.data.route=="north-114"' "$scratch/route" >/dev/null 2>&1; then printf '%s\n' 'reader route data = north-114: ✗ [DQ:value]'; failed=1; fi
for path in configmaps secrets configmaps/offlimits; do
  status=$(request "$token" "$path" /dev/null || true)
  if ! test "$status" = 403; then printf '%s\n' "reader GET $path status = 403: ✗ [DQ:denied_${path//\//_}]"; failed=1; fi
done
unset token
exit "$failed"
