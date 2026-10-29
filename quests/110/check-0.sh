set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
dns_answer_has() {
  local result=$1 expected=$2
  awk -v expected="$expected" '
    /^[[:space:]]*Name([[:space:]]+[0-9]+)?:/ { answer=1; next }
    answer && /^[[:space:]]*Address([[:space:]]+[0-9]+)?:/ {
      sub(/^[^:]*:[[:space:]]*/, ""); split($0, fields, /[[:space:]]+/)
      if (fields[1] == expected) found=1
    }
    END { exit !found }
  ' <<<"$result"
}
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
client=$(kubectl get deployment client -o json 2>/dev/null || true)
check 'deployment/client dnsPolicy = None [DQ:dns_policy]' '.spec.template.spec.dnsPolicy=="None"' "$client"
if ! test -n "$dns_ip" || ! jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsConfig.nameservers==[$ip]' <<<"$client" >/dev/null 2>&1; then printf '%s\n' 'deployment/client nameservers = [station-dns Service IP]: ✗ [DQ:nameserver]'; failed=1; fi
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
lookup=''
if test -n "$dns_ip" && test -n "$expected"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup station.internal "$dns_ip" 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$expected" || ! dns_answer_has "$lookup" "$expected"; then printf '%s\n' 'client DNS station.internal answer = expected-dns-address: ✗ [DQ:answer]'; failed=1; fi
exit "$failed"
