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
role=$(timeout 2s kubectl get role station-reader -o json 2>/dev/null || true)
check 'role/station-reader rules = named route get only [DQ:role]' '.rules==[{apiGroups:[""],resources:["configmaps"],resourceNames:["route"],verbs:["get"]}]' "$role"
binding=$(timeout 2s kubectl get rolebinding station-reader -o json 2>/dev/null || true)
if ! jq -e --arg ns "$DQ_NAMESPACE" '.subjects==[{kind:"ServiceAccount",name:"controller",namespace:$ns}]' <<<"$binding" >/dev/null 2>&1; then printf '%s\n' 'rolebinding/station-reader subjects = controller in bay namespace: ✗ [DQ:binding]'; failed=1; fi
controller=$(timeout 2s kubectl exec --pod-running-timeout=2s deployment/controller -- cat /credential/token 2>/dev/null || true)
observer=$(timeout 2s kubectl exec --pod-running-timeout=2s deployment/observer -- cat /credential/token 2>/dev/null || true)
status=$(request "$controller" configmaps/route "$scratch/route" || true)
if ! test "$status" = 200; then printf '%s\n' 'controller GET configmaps/route status = 200: ✗ [DQ:allowed]'; failed=1; fi
if ! jq -e '.data.route=="north-125"' "$scratch/route" >/dev/null 2>&1; then printf '%s\n' 'controller route data = north-125: ✗ [DQ:value]'; failed=1; fi
for path in configmaps configmaps/offlimits secrets secrets/control; do
  status=$(request "$controller" "$path" /dev/null || true)
  if ! test "$status" = 403; then printf '%s\n' "controller GET $path status = 403: ✗ [DQ:denied_${path//\//_}]"; failed=1; fi
done
status=$(request "$observer" configmaps/route /dev/null || true)
if ! test "$status" = 403; then printf '%s\n' 'observer GET configmaps/route status = 403: ✗ [DQ:observer]'; failed=1; fi
unset controller observer
exit "$failed"
