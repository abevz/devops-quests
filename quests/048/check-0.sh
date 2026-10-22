set -euo pipefail
cd ~/quest
source platform.env
test "$(stat -c %a station-token)" = 600
token=$(cat station-token)
curl -fsS -H "X-Vault-Token: $token" "$VAULT_ADDR/v1/auth/token/lookup-self" | jq -e '.data.ttl>90 and .data.renewable==true and .data.explicit_max_ttl==600 and (.data.policies|sort)==["default","rail-reader"]' >/dev/null
cat > reader-capabilities.json <<'CAPABILITY_INPUT'
{"paths": ["secret/data/dispatch", "secret/data/other", "sys/mounts"]}
CAPABILITY_INPUT
curl -fsS -X POST -H "X-Vault-Token: $token" -H 'Content-Type: application/json' --data-binary @reader-capabilities.json "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '(.data // .) | .["secret/data/dispatch"]==["read"] and .["secret/data/other"]==["deny"] and .["sys/mounts"]==["deny"]' >/dev/null
cat > issuer-capabilities.json <<'CAPABILITY_INPUT'
{"paths": ["sys/policies/acl/rail-reader", "auth/token/create/rail-station", "auth/token/create/other"]}
CAPABILITY_INPUT
curl -fsS -X POST -H "X-Vault-Token: $VAULT_MANAGER_TOKEN" -H 'Content-Type: application/json' --data-binary @issuer-capabilities.json "$VAULT_ADDR/v1/sys/capabilities-self" | jq -e '(.data // .) | .["sys/policies/acl/rail-reader"]==["deny"] and .["auth/token/create/rail-station"]==["update"] and .["auth/token/create/other"]==["deny"]' >/dev/null
kubectl get deployment reader -o json | DQ_CHECK_TOKEN="$token" python3 -c 'import json,os,sys; d=json.load(sys.stdin); e=d["spec"]["template"]["spec"]["containers"][0]["env"]; assert e==[{"name":"ROUTE","valueFrom":{"secretKeyRef":{"name":"route-secret","key":"value"}}}]; assert os.environ["DQ_CHECK_TOKEN"] not in json.dumps(d), "Keep the Vault token out of the workload"'
kubectl rollout status deployment/reader --timeout=3s >/dev/null
test "$(kubectl exec deployment/reader -- cat /tmp/route)" = north-secret
