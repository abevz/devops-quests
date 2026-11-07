set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    service=get('service','station-dns');d=get('deployment','client');spec=d['spec']['template']['spec']
    require(spec.get('dnsPolicy')=='None','dns_policy')
    require(bool(spec.get('dnsConfig',{}).get('nameservers')) and set(spec['dnsConfig']['nameservers'])=={service['spec']['clusterIP']},'nameserver')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'nameserver'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
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
expected=$(cat /run/dq/facts/0/expected-dns-address 2>/dev/null || true)
lookup=''
if test -n "$dns_ip" && test -n "$expected"; then
  if ! lookup=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- nslookup station.internal "$dns_ip" 2>/dev/null); then lookup=''; fi
fi
if ! test -n "$expected" || ! dns_answer_has "$lookup" "$expected"; then printf '%s\n' 'client DNS station.internal answer = expected-dns-address: ✗ [DQ:answer]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    ingress=get('ingress','board');service=get('service','board');spec=ingress['spec']
    expected=json.loads(Path('/run/dq/facts/0/ingress-target.json').read_text())['class']
    require(spec.get('ingressClassName')==expected,'ingress_class')
    paths=[p for r in spec.get('rules',[]) if r.get('host')=='station.internal' for p in r.get('http',{}).get('paths',[]) if p.get('path')=='/' and p.get('pathType') in ('Prefix','Exact')]
    exact=[p for p in paths if p.get('pathType')=='Exact'];paths=exact or paths
    require(bool(paths),'host')
    for path in paths:
        backend=path.get('backend',{}).get('service',{});port=backend.get('port',{})
        require(backend.get('name')=='board','backend')
        matched=[p for p in service['spec'].get('ports',[]) if (p.get('port')==port.get('number') if 'number' in port else p.get('name')==port.get('name')) and p.get('protocol','TCP')=='TCP']
        require(len(matched)==1,'backend')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'backend'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
check() { local label=$1 expression=$2 document=$3; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗"; failed=1; fi; }
url=http://station.internal:8000
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 3 --header='Host: station.internal' "$url" 2>/dev/null)" = north-110; then printf '%s\n' 'matching Host response = north-110: ✗ [DQ:http]'; failed=1; fi
if test -n "$url" && timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 3 --header='Host: wrong.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'wrong Host request fails: ✗ [DQ:wrong]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
