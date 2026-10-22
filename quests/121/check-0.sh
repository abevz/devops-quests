set -euo pipefail
cd ~/quest
name=dq-webhook-${DQ_NAMESPACE#dq-}
kubectl get validatingwebhookconfiguration "$name" -o json | jq -e --arg ns "$DQ_NAMESPACE" '.webhooks[0].failurePolicy=="Fail" and .webhooks[0].timeoutSeconds==2 and (.webhooks[0].clientConfig.url|endswith("/validate"))' >/dev/null
kubectl get configmap route -o json | jq -e '.data.route=="north-121"' >/dev/null
kubectl get deployment board -o json | jq -e '.status.readyReplicas==1' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-121
kubectl get configmap route -o json | jq '.data.route="closed" | del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,.metadata.managedFields)' > /tmp/invalid-route.json
if kubectl apply --dry-run=server -f /tmp/invalid-route.json >/tmp/admission-denial.log 2>&1; then exit 1; fi
grep -F 'Station route must be north-121' /tmp/admission-denial.log >/dev/null
