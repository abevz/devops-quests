set -euo pipefail
cd ~/quest
failed=0
name=dq-webhook-${DQ_NAMESPACE#dq-}
webhook=$(kubectl get validatingwebhookconfiguration "$name" -o json 2>/dev/null || true)
namespace=$(kubectl get namespace "$DQ_NAMESPACE" -o json 2>/dev/null || true)
installation=$(jq -r '.metadata.labels["devops-quests.installation"] // ""' <<<"$namespace" 2>/dev/null || true)
if ! jq -e '.webhooks | length==1' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook configuration webhooks length = 1: ✗'
  failed=1
fi
if ! jq -e '.webhooks[0].name=="route.training.devops-quests.local"' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook name = route.training.devops-quests.local: ✗'
  failed=1
fi
if ! jq -e '.webhooks[0].failurePolicy=="Fail"' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook failurePolicy = Fail: ✗'
  failed=1
fi
if ! jq -e '.webhooks[0].timeoutSeconds==2' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook timeoutSeconds = 2: ✗'
  failed=1
fi
if ! jq -e --arg url "https://$name:8443/validate" '.webhooks[0].clientConfig.url==$url' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook clientConfig.url = https://dq-webhook-<bay>:8443/validate: ✗'
  failed=1
fi
if ! python3 - "$webhook" <<'DQ_CA'
import base64
import json
import sys
from pathlib import Path
try:
    actual = base64.b64decode(json.loads(sys.argv[1])["webhooks"][0]["clientConfig"]["caBundle"], validate=True).strip()
    expected = Path("admission-ca.pem").read_bytes().strip()
    if not expected or actual != expected:
        raise ValueError("CA mismatch")
except (KeyError, IndexError, TypeError, ValueError, OSError):
    sys.exit(1)
DQ_CA
then
  printf '%s\n' 'webhook caBundle = admission-ca.pem: ✗'
  failed=1
fi
if ! test -n "$installation" || ! jq -e --arg install "$installation" --arg run "${DQ_NAMESPACE#dq-}" '.webhooks[0].namespaceSelector=={"matchLabels":{"devops-quests.installation":$install,"devops-quests.run":$run}}' <<<"$webhook" >/dev/null 2>&1; then
  printf '%s\n' 'webhook namespaceSelector = bay installation and run labels: ✗'
  failed=1
fi
route=$(kubectl get configmap route -o json 2>/dev/null || true)
if ! jq -e '.data.route=="north-121"' <<<"$route" >/dev/null 2>&1; then
  printf '%s\n' 'configmap/route data.route = north-121: ✗'
  failed=1
fi
if ! kubectl get deployment board -o json 2>/dev/null | jq -e '.status.readyReplicas==1' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board readyReplicas = 1: ✗'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-121; then
  printf '%s\n' 'deployment/client → board:8080 = north-121: ✗'
  failed=1
fi
tmpdir=$(mktemp -d)
trap 'rm -f "$tmpdir/valid.json" "$tmpdir/invalid.json" "$tmpdir/denial.log"; rmdir "$tmpdir"' EXIT
if ! jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.managedFields)' <<<"$route" > "$tmpdir/valid.json" 2>/dev/null || ! kubectl apply --dry-run=server -f "$tmpdir/valid.json" >/dev/null 2>&1; then
  printf '%s\n' 'configmap/route north-121 server dry-run: ✗'
  failed=1
fi
if ! jq '.data.route="closed" | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.managedFields)' <<<"$route" > "$tmpdir/invalid.json" 2>/dev/null; then
  printf '%s\n' 'configmap/route closed dry-run input: ✗'
  failed=1
elif kubectl apply --dry-run=server -f "$tmpdir/invalid.json" > "$tmpdir/denial.log" 2>&1; then
  printf '%s\n' 'configmap/route closed server dry-run rejects: ✗'
  failed=1
elif ! grep -F 'Station route must be north-121' "$tmpdir/denial.log" >/dev/null; then
  printf '%s\n' 'closed denial = Station route must be north-121: ✗'
  failed=1
fi
exit "$failed"
