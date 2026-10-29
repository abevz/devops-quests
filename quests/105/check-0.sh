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
dns=$(kubectl get deployment station-dns -o json 2>/dev/null || true)
service=$(kubectl get service station-dns -o json 2>/dev/null || true)
check 'station-dns command = /coredns -conf /etc/station/Corefile [DQ:command]' '.spec.template.spec.containers[0].command==["/coredns","-conf","/etc/station/Corefile"]' "$dns"
check 'station-dns ports = TCP/UDP 53 to 1053 [DQ:ports]' '[.spec.ports[] | [.port,.targetPort,.protocol]] | sort == [[53,1053,"TCP"],[53,1053,"UDP"]]' "$service"
core=$(kubectl get configmap station-dns -o jsonpath='{.data.Corefile}' 2>/dev/null || true)
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
if ! test -n "$expected" || ! python3 - "$core" "$expected" <<'DQ_CORE'
import re,sys
actual=re.sub(r'\s+',' ',sys.argv[1]).strip()
expected='.:1053 { errors hosts { '+sys.argv[2].strip()+' north.station.internal ttl 1 } }'
sys.exit(actual!=expected)
DQ_CORE
then printf '%s\n' 'station-dns Corefile matches supplied hosts, port and TTL: ✗ [DQ:core]'; failed=1; fi
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
client=$(kubectl get deployment client -o json 2>/dev/null || true)
check 'deployment/client dnsPolicy = None [DQ:dns_policy]' '.spec.template.spec.dnsPolicy=="None"' "$client"
if ! test -n "$dns_ip" || ! jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsConfig.nameservers==[$ip]' <<<"$client" >/dev/null 2>&1; then printf '%s\n' 'deployment/client nameservers = [station-dns Service IP]: ✗ [DQ:nameserver]'; failed=1; fi
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
lookup=''
if test -n "$dns_ip" && test -n "$expected"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup north.station.internal "$dns_ip" 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$expected" || ! dns_answer_has "$lookup" "$expected"; then printf '%s\n' 'client DNS north.station.internal answer = expected-dns-address: ✗ [DQ:answer]'; failed=1; fi
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://north.station.internal:8080 2>/dev/null)" = north-105; then printf '%s\n' 'client north.station.internal:8080 = north-105: ✗ [DQ:http]'; failed=1; fi
exit "$failed"
