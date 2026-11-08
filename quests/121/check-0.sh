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
name=dq-webhook-${DQ_NAMESPACE#dq-}
webhook=$(kubectl get validatingwebhookconfiguration "$name" -o json 2>/dev/null || true)
namespace=$(kubectl get namespace "$DQ_NAMESPACE" -o json 2>/dev/null || true)
installation=$(jq -r '.metadata.labels["devops-quests.installation"] // ""' <<<"$namespace" 2>/dev/null || true)
if ! jq -e '.webhooks | length==1' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook configuration webhooks length = 1: ✗ [DQ:count]'
  failed=1
fi
if ! jq -e '.webhooks[0].name=="route.training.devops-quests.local"' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook name = route.training.devops-quests.local: ✗ [DQ:name]'
  failed=1
fi
if ! jq -e '.webhooks[0].failurePolicy=="Fail"' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook failurePolicy = Fail: ✗ [DQ:failure_policy]'
  failed=1
fi
if ! jq -e '.webhooks[0].timeoutSeconds==2' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook timeoutSeconds = 2: ✗ [DQ:timeout]'
  failed=1
fi
if ! jq -e --arg url "https://$name:8443/validate" '.webhooks[0].clientConfig.url==$url' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook clientConfig.url = https://dq-webhook-<bay>:8443/validate: ✗ [DQ:url]'
  failed=1
fi
if ! python3 -I - /dev/fd/3 3<<<"$webhook" <<'DQ_CA'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import base64
import re
import json
import sys
from pathlib import Path
try:
    def certificate(value):
        match=re.fullmatch(rb'\s*-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+)-----END CERTIFICATE-----\s*',value)
        if not match:raise ValueError('single PEM certificate')
        return base64.b64decode(re.sub(rb'\s+',b'',match[1]),validate=True)
    actual=certificate(base64.b64decode(json.loads(sys.argv[1])["webhooks"][0]["clientConfig"]["caBundle"],validate=True))
    expected=certificate(Path('admission-ca.pem').read_bytes())
    if not expected or actual != expected:
        raise ValueError("CA mismatch")
except (KeyError, IndexError, TypeError, ValueError, OSError):
    sys.exit(1)
DQ_CA
then
  printf '%s\n' 'webhook caBundle = admission-ca.pem: ✗ [DQ:ca]'
  failed=1
fi
if ! test -n "$installation" || ! python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 3<<<"$webhook" 4<<<"$installation" 5<<<"${DQ_NAMESPACE#dq-}" <<'DQ_NAMESPACE_SCOPE'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
def simple_selector(value, labels):
    if not isinstance(value,dict) or set(value)-{'matchLabels','matchExpressions'}:return False
    matches=value.get('matchLabels',{})
    clauses=value.get('matchExpressions',[])
    if not isinstance(matches,dict) or not isinstance(clauses,list):return False
    if set(matches)-set(labels) or any(e.get('key') not in labels for e in clauses):return False
    for key,expected in labels.items():
        allowed={matches[key]} if key in matches else None
        exclusions=set();exists=key in matches
        for clause in clauses:
            if clause['key']!=key:continue
            operator=clause.get('operator');values=clause.get('values',[])
            if operator=='In':
                if not values:return False
                allowed=set(values) if allowed is None else allowed & set(values)
                exists=True
            elif operator=='NotIn':exclusions.update(values)
            elif operator=='Exists':exists=True
            else:return False
        if allowed is None or not exists or allowed-exclusions!={expected}:return False
    return True

try:
    scope=json.loads(sys.argv[1])['webhooks'][0]['namespaceSelector']
    ok=simple_selector(scope,{'devops-quests.installation':sys.argv[2],'devops-quests.run':sys.argv[3]})
except (ValueError,KeyError,IndexError,TypeError,AttributeError):ok=False
sys.exit(not ok)
DQ_NAMESPACE_SCOPE
then
  printf '%s\n' 'webhook namespaceSelector = bay installation and run labels: ✗ [DQ:namespace]'
  failed=1
fi
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
route=$(kubectl get configmap route -o json 2>/dev/null || true)
if ! jq -e '.data.route=="north-121"' <<<"$route" >/dev/null 2>&1; then
  printf '%s\n' 'configmap/route data.route = north-121: ✗ [DQ:route]'
  failed=1
fi
tmpdir=$(mktemp -d)
trap 'rm -f "$tmpdir/valid.json" "$tmpdir/invalid.json" "$tmpdir/denial.log"; rmdir "$tmpdir"' EXIT
if ! jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.managedFields)' <<<"$route" > "$tmpdir/valid.json" 2>/dev/null || ! kubectl apply --dry-run=server -f "$tmpdir/valid.json" >/dev/null 2>&1; then
  printf '%s\n' 'configmap/route north-121 server dry-run: ✗ [DQ:valid]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
route=$(kubectl get configmap route -o json 2>/dev/null || true)
tmpdir=$(mktemp -d)
trap 'rm -f "$tmpdir/valid.json" "$tmpdir/invalid.json" "$tmpdir/denial.log"; rmdir "$tmpdir"' EXIT
if ! jq '.data.route="closed" | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.managedFields)' <<<"$route" > "$tmpdir/invalid.json" 2>/dev/null; then
  printf '%s\n' 'configmap/route closed dry-run input: ✗ [DQ:invalid_input]'
  failed=1
elif kubectl apply --dry-run=server -f "$tmpdir/invalid.json" > "$tmpdir/denial.log" 2>&1; then
  printf '%s\n' 'configmap/route closed server dry-run rejects: ✗ [DQ:denial]'
  failed=1
elif ! grep -F 'Station route must be north-121' "$tmpdir/denial.log" >/dev/null; then
  printf '%s\n' 'closed denial = Station route must be north-121: ✗ [DQ:denial_text]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! kubectl get deployment board -o json 2>/dev/null | jq -e '.status.readyReplicas==1' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board readyReplicas = 1: ✗ [DQ:ready]'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-121; then
  printf '%s\n' 'deployment/client → board:8080 = north-121: ✗ [DQ:http]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
