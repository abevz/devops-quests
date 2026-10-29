set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
if ! remaining=$(kubectl get configmap station --ignore-not-found -o name 2>/dev/null); then printf '%s\n' 'query configmap/station: ✗ [DQ:config_query]'; failed=1; elif test -n "$remaining"; then printf '%s\n' 'configmap/station absent: ✗ [DQ:config_absent]'; failed=1; fi
if ! remaining=$(kubectl get secret station-record --ignore-not-found -o name 2>/dev/null); then printf '%s\n' 'query secret/station-record: ✗ [DQ:secret_query]'; failed=1; elif test -n "$remaining"; then printf '%s\n' 'secret/station-record absent: ✗ [DQ:secret_absent]'; failed=1; fi
control=$(kubectl get secret control -o json 2>/dev/null || true)
contract=$(cat /run/dq/facts/0/cleanup-contract.json 2>/dev/null || true)
uid=$(jq -r '.control_uid // ""' <<<"$contract" 2>/dev/null || true)
if ! test -n "$uid" || ! jq -e --arg uid "$uid" '.metadata.uid==$uid' <<<"$control" >/dev/null 2>&1; then printf '%s\n' 'control Secret UID = cleanup-contract.json: ✗ [DQ:control_uid]'; failed=1; fi
if ! printf '%s' "$control" | python3 -c 'import hashlib,json,sys; from pathlib import Path; contract=json.loads(Path("/run/dq/facts/0/cleanup-contract.json").read_text()); control=json.load(sys.stdin); digest=hashlib.sha256(json.dumps(control["data"],sort_keys=True).encode()).hexdigest(); assert digest==contract["control_hash"]' >/dev/null 2>&1; then printf '%s\n' 'control Secret data hash = cleanup-contract.json: ✗ [DQ:control_hash]'; failed=1; fi
exit "$failed"
