set -euo pipefail
cd ~/quest
failed=0
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
deployments=$(timeout 2s kubectl get deployment blue green -o json 2>/dev/null || true)
check blue_replicas 'blue replicas = 3' 'any(.items[]?;.metadata.name=="blue" and .spec.replicas==3)' "$deployments"
check blue_ready 'blue readyReplicas = 3' 'any(.items[]?;.metadata.name=="blue" and .status.readyReplicas==3)' "$deployments"
check green_replicas 'green replicas = 1' 'any(.items[]?;.metadata.name=="green" and .spec.replicas==1)' "$deployments"
check green_ready 'green readyReplicas = 1' 'any(.items[]?;.metadata.name=="green" and .status.readyReplicas==1)' "$deployments"
service=$(timeout 2s kubectl get service board -o json 2>/dev/null || true)
check selector_canary 'service/board selector = release board' '.spec.selector=={release:"board"}' "$service"
endpoints=$(timeout 2s kubectl get endpointslices -l kubernetes.io/service-name=board -o json 2>/dev/null || true)
check endpoints 'four unique ready EndpointSlice target names' '[.items[].endpoints[] | select(.conditions.ready==true and (.targetRef.name | type=="string" and length>0)) | .targetRef.name] | unique | length==4' "$endpoints"
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
probe_count=0
for version in blue green; do
  ips=$(timeout 2s kubectl get pods -l "app=$version" -o jsonpath='{.items[*].status.podIP}' 2>/dev/null || true)
  if ! test -n "$ips"; then printf '%s\n' "$version Pod IPs present: ✗ [DQ:ips_$version]"; failed=1; fi
  for ip in $ips; do
    probe_count=$((probe_count+1))
    (
      if ! test "$(timeout 3s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 2 "http://$ip:8080" 2>/dev/null)" = "$version-115"; then printf '%s\n' "$version Pod $ip:8080 = $version-115: ✗ [DQ:pod_$version]" > "$probe_dir/$probe_count"; fi
    ) &
  done
done
wait
for diagnostic in "$probe_dir"/*; do
  if test -f "$diagnostic"; then cat "$diagnostic"; failed=1; fi
done
case "$(timeout 3s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 2 http://board:8080 2>/dev/null)" in blue-115|green-115) ;; *) printf '%s\n' 'board:8080 = blue-115 or green-115: ✗ [DQ:canary_http]'; failed=1;; esac
exit "$failed"
