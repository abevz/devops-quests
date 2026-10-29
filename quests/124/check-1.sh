set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
volume=$(jq -r '.volume // ""' /run/dq/facts/0/volume-contract.json 2>/dev/null || true)
uid=$(jq -r '.pv_uid // ""' /run/dq/facts/0/volume-contract.json 2>/dev/null || true)
if ! test -n "$volume"; then printf '%s\n' 'volume-contract.json volume exists: ✗ [DQ:volume]'; failed=1; fi
if ! test -n "$uid"; then printf '%s\n' 'volume-contract.json pv_uid exists: ✗ [DQ:pv_uid_fact]'; failed=1; fi
pv=$(kubectl get pv "$volume" -o json 2>/dev/null || true)
if ! test -n "$uid" || ! jq -e --arg uid "$uid" '.metadata.uid==$uid' <<<"$pv" >/dev/null 2>&1; then printf '%s\n' 'PV UID = volume-contract.json pv_uid: ✗ [DQ:pv_uid]'; failed=1; fi
if ! test -n "$volume" || ! jq -e --arg volume "$volume" '.spec.storageClassName==$volume' <<<"$pv" >/dev/null 2>&1; then printf '%s\n' 'PV storageClassName = volume name: ✗ [DQ:class]'; failed=1; fi
check 'PV reclaimPolicy = Retain [DQ:reclaim]' '.spec.persistentVolumeReclaimPolicy=="Retain"' "$pv"
check 'PV phase = Bound [DQ:phase]' '.status.phase=="Bound"' "$pv"
claim_uid=$(kubectl get pvc ledger -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if ! test -n "$claim_uid" || ! jq -e --arg claim "$claim_uid" '.spec.claimRef.uid==$claim' <<<"$pv" >/dev/null 2>&1; then printf '%s\n' 'PV claimRef UID = current ledger PVC UID: ✗ [DQ:claimref]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-124; then printf '%s\n' 'board:8080 = north-124: ✗ [DQ:http]'; failed=1; fi
original=$(cat /run/dq/facts/0/original-claim-uid 2>/dev/null || true)
if ! test -n "$claim_uid" || ! test -n "$original" || test "$claim_uid" = "$original"; then printf '%s\n' 'ledger PVC UID differs from original-claim-uid: ✗ [DQ:replacement]'; failed=1; fi
exit "$failed"
