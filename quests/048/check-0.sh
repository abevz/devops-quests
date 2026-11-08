set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
test "$(stat -c %a station-token)" = 600
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
token=$(cat station-token)
curl -fsS -H "X-Vault-Token: $token" "$VAULT_ADDR/v1/auth/token/lookup-self" | jq -e '.data.ttl>90 and .data.renewable==true and .data.explicit_max_ttl==600 and (.data.policies|sort)==["default","rail-reader"]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
token=$(cat station-token)
cat > reader-capabilities.json <<'CAPABILITY_INPUT'
{"paths": ["secret/data/dispatch", "secret/data/other", "sys/mounts"]}
CAPABILITY_INPUT
curl -fsS -X POST -H "X-Vault-Token: $token" -H 'Content-Type: application/json' --data-binary @reader-capabilities.json "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '(.data // .) | .["secret/data/dispatch"]==["read"] and .["secret/data/other"]==["deny"] and .["sys/mounts"]==["deny"]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
cat > issuer-capabilities.json <<'CAPABILITY_INPUT'
{"paths": ["sys/policies/acl/rail-reader", "auth/token/create/rail-station", "auth/token/create/other"]}
CAPABILITY_INPUT
curl -fsS -X POST -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @issuer-capabilities.json "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '(.data // .) | .["sys/policies/acl/rail-reader"]==["deny"] and .["auth/token/create/rail-station"]==["update"] and .["auth/token/create/other"]==["deny"]' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
token=$(cat station-token)
kubectl get deployment reader -o json | DQ_CHECK_TOKEN="$token" VAULT_MANAGER_TOKEN="${VAULT_MANAGER_TOKEN:-}" VAULT_READER_TOKEN="${VAULT_READER_TOKEN:-}" python3 -I -c 'import json,os,sys,subprocess
try:
    deployment=json.load(sys.stdin)
    workers=[item for item in deployment['"'"'spec'"'"']['"'"'template'"'"']['"'"'spec'"'"']['"'"'containers'"'"'] if item.get('"'"'name'"'"')=='"'"'worker'"'"']
    assert len(workers)==1
    entries=[entry for entry in workers[0].get('"'"'env'"'"',[]) if entry.get('"'"'name'"'"')=='"'"'ROUTE'"'"']
    assert entries
    effective=entries[-1]
    assert effective.get('"'"'value'"'"') in (None,'"'"''"'"')
    reference=effective.get('"'"'valueFrom'"'"',{}).get('"'"'secretKeyRef'"'"',{})
    assert reference.get('"'"'name'"'"')=='"'"'route-secret'"'"' and reference.get('"'"'key'"'"')=='"'"'value'"'"'
    tokens={value for value in (os.environ.get('"'"'DQ_CHECK_TOKEN'"'"'),os.environ.get('"'"'VAULT_MANAGER_TOKEN'"'"'),os.environ.get('"'"'VAULT_READER_TOKEN'"'"')) if value}
    assert tokens and all(value not in json.dumps(deployment) for value in tokens)
    def observed(args):
        return subprocess.check_output(['"'"'kubectl'"'"']+args,stderr=subprocess.DEVNULL,timeout=4)
    replicasets=json.loads(observed(['"'"'get'"'"','"'"'replicasets'"'"','"'"'-o'"'"','"'"'json'"'"']))
    pods=json.loads(observed(['"'"'get'"'"','"'"'pods'"'"','"'"'-o'"'"','"'"'json'"'"']))
    uid=deployment['"'"'metadata'"'"']['"'"'uid'"'"']
    owners={rs['"'"'metadata'"'"']['"'"'uid'"'"'] for rs in replicasets.get('"'"'items'"'"',[]) if any(ref.get('"'"'kind'"'"')=='"'"'Deployment'"'"' and ref.get('"'"'uid'"'"')==uid and ref.get('"'"'controller'"'"') is True for ref in rs.get('"'"'metadata'"'"',{}).get('"'"'ownerReferences'"'"',[]))}
    active=[pod for pod in pods.get('"'"'items'"'"',[]) if pod.get('"'"'metadata'"'"',{}).get('"'"'deletionTimestamp'"'"') is None and pod.get('"'"'status'"'"',{}).get('"'"'phase'"'"') not in ('"'"'Failed'"'"','"'"'Succeeded'"'"') and any(ref.get('"'"'kind'"'"')=='"'"'ReplicaSet'"'"' and ref.get('"'"'uid'"'"') in owners and ref.get('"'"'controller'"'"') is True for ref in pod.get('"'"'metadata'"'"',{}).get('"'"'ownerReferences'"'"',[]))]
    assert active
    for pod in active:
        assert pod.get('"'"'status'"'"',{}).get('"'"'phase'"'"')=='"'"'Running'"'"'
        for container in pod['"'"'spec'"'"']['"'"'containers'"'"']:
            environment=observed(['"'"'exec'"'"','"'"'--pod-running-timeout=2s'"'"',pod['"'"'metadata'"'"']['"'"'name'"'"'],'"'"'-c'"'"',container['"'"'name'"'"'],'"'"'--'"'"','"'"'env'"'"'])
            assert all(value.encode() not in environment for value in tokens)
except Exception:
    sys.exit(1)
'
test "$(kubectl exec deployment/reader -c worker -- cat /tmp/route)" = north-secret
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_4]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/reader --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
exit "$failed"
