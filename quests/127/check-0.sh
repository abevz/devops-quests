set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
failed=0
selector_ok() {
  python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 /dev/fd/6 3<<<"$1" 4<<<"$pods" 5<<<"$2" 6<<<"$3" <<'DQ_SELECTOR'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service,pods=json.loads(sys.argv[1]),json.loads(sys.argv[2])['items'];key,value=sys.argv[3:5]
    selector=service['spec']['selector']
    intended=[p for p in pods if p['metadata'].get('labels',{}).get(key)==value and not p['metadata'].get('deletionTimestamp')]
    def matches(p):return all(p['metadata'].get('labels',{}).get(k)==v for k,v in selector.items())
    ok=isinstance(selector,dict) and selector.get(key)==value and bool(intended) and all(matches(p) for p in intended) and all(not matches(p) or p['metadata'].get('labels',{}).get(key)==value for p in pods)
except (ValueError,KeyError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_SELECTOR
}
pods=$(timeout 2s kubectl get pods -o json 2>/dev/null || true)
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
if ! python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$service" 4<<<"$pods" <<'DQ_METRICS_PORT'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    service=json.loads(sys.argv[1]);pods=json.loads(sys.argv[2])['items']
    ports=[p for p in service['spec']['ports'] if p.get('name')=='http']
    port=ports[0] if len(ports)==1 else {}
    published=port.get('port')==8080 and port.get('protocol','TCP')=='TCP'
    value=port.get('targetPort',port.get('port'))
    if type(value) is int:target=value==8080
    elif isinstance(value,str):
        targets=[p for p in pods if p.get('metadata',{}).get('labels',{}).get('app')=='board' and not p.get('metadata',{}).get('deletionTimestamp')]
        target=bool(targets)
        for pod in targets:
            found=[p['containerPort'] for c in pod['spec']['containers'] for p in c.get('ports',[]) if p.get('name')==value and p.get('protocol','TCP')=='TCP']
            target=target and found==[8080]
    else:target=False
except (ValueError,KeyError,TypeError,AttributeError):published=target=False
if not published:print('service board HTTP port = 8080: ✗ [DQ:port]')
if not target:print('service board HTTP target reaches application listener: ✗ [DQ:target_port]')
sys.exit(not (published and target))
DQ_METRICS_PORT
then failed=1; fi
if ! selector_ok "$service" app board; then printf '%s\n' 'service selector retains only the supplied board workload: ✗ [DQ:selector]'; failed=1; fi
exit "$failed"
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/prometheus-target.json 2>/dev/null || true)
up=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=up%7Bjob%3D%22board%22%7D" 2>/dev/null || true)
targets=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/targets?state=active" 2>/dev/null || true)
query=up
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
check target_health 'one active board target is up with empty lastError' 'any(.data.activeTargets[]?;.labels.job=="board" and .health=="up" and .lastError=="")' "$targets"
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/prometheus-target.json 2>/dev/null || true)
sum=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=sum%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
count=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 "$url/api/v1/query?query=count%28station_queue_depth%7Bjob%3D%22board%22%2Croute%3D%22north%22%7D%29" 2>/dev/null || true)
query=sum
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
query=count
  case "$query" in up) doc=$up; expected=1;; sum) doc=$sum; expected=7;; count) doc=$count; expected=2;; esac
  check "${query}_status" "$query query status = success" '.status=="success"' "$doc"
  check "${query}_count" "$query query returns one result" '(.data.result|length)==1' "$doc"
  if ! jq -e --arg expected "$expected" '.data.result[0].value[1]==$expected' <<<"$doc" >/dev/null 2>&1; then printf '%s\n' "$query query value = $expected: ✗ [DQ:${query}_value]"; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
