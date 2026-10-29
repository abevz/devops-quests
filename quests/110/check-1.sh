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
check 'deployment/client dnsPolicy = None' '.spec.template.spec.dnsPolicy=="None"' "$client"
if ! test -n "$dns_ip" || ! jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsConfig.nameservers==[$ip]' <<<"$client" >/dev/null 2>&1; then printf '%s\n' 'deployment/client nameservers = [station-dns Service IP]: ✗'; failed=1; fi
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
lookup=''
if test -n "$dns_ip" && test -n "$expected"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup station.internal "$dns_ip" 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$expected" || ! dns_answer_has "$lookup" "$expected"; then printf '%s\n' 'client DNS station.internal answer = expected-dns-address: ✗'; failed=1; fi
url=http://station.internal:8000
class=$(jq -r '.class // ""' /run/dq/facts/0/ingress-target.json 2>/dev/null || true)
ingress=$(kubectl get ingress board -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.ingressClassName==$class' <<<"$ingress" >/dev/null 2>&1; then printf '%s\n' 'ingress/board class = supplied private class: ✗'; failed=1; fi
check 'ingress/board first host = station.internal' '.spec.rules[0].host=="station.internal"' "$ingress"
check 'ingress/board first path = /' '.spec.rules[0].http.paths[0].path=="/"' "$ingress"
check 'ingress/board first pathType = Prefix' '.spec.rules[0].http.paths[0].pathType=="Prefix"' "$ingress"
check 'ingress/board first backend = board:8080' '.spec.rules[0].http.paths[0].backend.service=={name:"board",port:{number:8080}}' "$ingress"
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: station.internal' "$url" 2>/dev/null)" = north-110; then printf '%s\n' 'matching Host response = north-110: ✗'; failed=1; fi
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 --header='Host: wrong.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'wrong Host request fails: ✗'; failed=1; fi
exit "$failed"
