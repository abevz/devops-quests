set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
entrypoint_version=''
if jq -e '[.spec.template.spec.containers[]? | select(.name=="worker")] | length==1 and ((.[0].command//[])|length)==0' <<<"$dns" >/dev/null 2>&1; then
  entrypoint_version=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/station-dns -c worker -- /proc/1/exe -version 2>/dev/null || true)
fi
if ! python3 -I - /dev/fd/3 /dev/fd/4 /dev/fd/5 3<<<"$dns" 4<<<"$service" 5<<<"$entrypoint_version" <<'DQ_DNS_RUNTIME'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    deployment=json.loads(sys.argv[1]);service=json.loads(sys.argv[2]);workers=[c for c in deployment['spec']['template']['spec']['containers'] if c.get('name')=='worker']
    if len(workers)!=1:raise ValueError('worker')
    worker=workers[0];argv=(worker.get('command') or [])+(worker.get('args') or [])
    if not worker.get('command'):
        verified=len(sys.argv)>3 and bool(sys.argv[3].splitlines()) and sys.argv[3].splitlines()[0].startswith('CoreDNS-')
        argv=['/coredns']+(worker.get('args') or []) if verified else []
    command=argv in (['/coredns','-conf','/etc/station/Corefile'],['/coredns','-conf=/etc/station/Corefile'],['/coredns','--conf','/etc/station/Corefile'],['/coredns','--conf=/etc/station/Corefile'])
    ports=[]
    for entry in service['spec']['ports']:
        protocol=entry.get('protocol','TCP');target=entry.get('targetPort',entry['port'])
        if isinstance(target,str):
            found=[p['containerPort'] for p in worker.get('ports',[]) if p.get('name')==target and p.get('protocol','TCP')==protocol]
            if len(found)!=1:raise ValueError('target port')
            target=found[0]
        ports.append((entry['port'],target,protocol))
    exposure=set(ports)=={(53,1053,'TCP'),(53,1053,'UDP')}
except (ValueError,KeyError,TypeError,AttributeError):command=exposure=False
if not command:print('station-dns uses the supplied CoreDNS configuration: ✗ [DQ:command]')
if not exposure:print('station-dns ports = TCP/UDP 53 to 1053: ✗ [DQ:ports]')
sys.exit(not (command and exposure))
DQ_DNS_RUNTIME
then failed=1; fi
resolver=$(jq -r '.spec.clusterIP // empty' <<<"$service" 2>/dev/null || true)
answer=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- nslookup north.station.internal "$resolver" 2>/dev/null || true)
if ! test -n "$expected" || ! test -n "$resolver" || ! dns_answer_has "$answer" "$expected"; then
  printf '%s\n' 'The private resolver must answer north.station.internal with the intended Service address: ✗ [DQ:core]'
  failed=1
fi
exit "$failed"
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
client=$(kubectl get deployment client -o json 2>/dev/null || true)
check 'deployment/client dnsPolicy = None [DQ:dns_policy]' '.spec.template.spec.dnsPolicy=="None"' "$client"
if ! test -n "$dns_ip" || ! jq -e --arg ip "$dns_ip" '.spec.template.spec.dnsConfig.nameservers==[$ip]' <<<"$client" >/dev/null 2>&1; then printf '%s\n' 'deployment/client nameservers = [station-dns Service IP]: ✗ [DQ:nameserver]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
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
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
dns_ip=$(kubectl get service station-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
lookup=''
if test -n "$dns_ip" && test -n "$expected"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- nslookup north.station.internal "$dns_ip" 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$expected" || ! dns_answer_has "$lookup" "$expected"; then printf '%s\n' 'client DNS north.station.internal answer = expected-dns-address: ✗ [DQ:answer]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -- wget -qO- -T 3 http://north.station.internal:8080 2>/dev/null)" = north-105; then printf '%s\n' 'client north.station.internal:8080 = north-105: ✗ [DQ:http]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
