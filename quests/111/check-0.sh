set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
statefulset=$(kubectl get statefulset shelf -o json 2>/dev/null || true)
pvc=$(kubectl get pvc ledger-shelf-0 -o json 2>/dev/null || true)
pod=$(kubectl get pod shelf-0 -o json 2>/dev/null || true)
for name in statefulset pvc pod; do
  case "$name" in statefulset) doc=$statefulset; file=original-statefulset-uid ;; pvc) doc=$pvc; file=original-pvc-uid ;; pod) doc=$pod; file=original-pod-uid ;; esac
  actual=$(jq -r '.metadata.uid // ""' <<<"$doc" 2>/dev/null || true)
  original=$(cat "/run/dq/facts/0/$file" 2>/dev/null || true)
  if ! test -n "$actual" || ! test -n "$original" || { if test "$name" = pod; then test "$actual" = "$original"; else test "$actual" != "$original"; fi; }; then printf '%s\n' "$name UID matches required relationship to $file: ✗ [DQ:uid_$name]"; failed=1; fi
done
check 'statefulset/shelf serviceName = shelf [DQ:service_name]' '.spec.serviceName=="shelf"' "$statefulset"
check 'statefulset/shelf readyReplicas = 1 [DQ:ready]' '.status.readyReplicas==1' "$statefulset"
check 'statefulset/shelf first volumeMounts = ledger at /data [DQ:mount]' '.spec.template.spec.containers[0].volumeMounts==[{name:"ledger",mountPath:"/data"}]' "$statefulset"
check 'service/shelf clusterIP = None [DQ:clusterip]' '.spec.clusterIP=="None"' "$(kubectl get service shelf -o json 2>/dev/null || true)"
check 'service/shelf selector = app:shelf [DQ:selector]' '.spec.selector=={app:"shelf"}' "$(kubectl get service shelf -o json 2>/dev/null || true)"
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s shelf-0 -- wget -qO- -T 3 http://shelf-0.shelf:8080 2>/dev/null)" = ledger-111; then printf '%s\n' 'shelf-0.shelf:8080 = ledger-111: ✗ [DQ:http]'; failed=1; fi
if ! timeout 4s kubectl exec --pod-running-timeout=2s shelf-0 -- nslookup -type=A "shelf-0.shelf.$DQ_NAMESPACE.svc.cluster.local." >/dev/null 2>&1; then printf '%s\n' 'shelf-0.shelf ordinal DNS lookup succeeds: ✗ [DQ:dns]'; failed=1; fi
exit "$failed"
