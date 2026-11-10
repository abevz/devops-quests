set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test -s /run/dq/facts/0/original-pvc-uid || ! test "$(kubectl get pvc ledger-shelf-0 -o jsonpath='{.metadata.uid}' 2>/dev/null)" = "$(cat /run/dq/facts/0/original-pvc-uid 2>/dev/null)"; then
  printf '%s\n' 'ledger-shelf-0 UID = /run/dq/facts/0/original-pvc-uid: ✗ [DQ:pvc]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
    service=get('service','shelf')['spec'];pod=get('pod','shelf-0');labels=pod['metadata']['labels'];selector=service.get('selector',{})
    require(service.get('clusterIP')=='None' and selector.get('app')=='shelf' and all(labels.get(k)==v for k,v in selector.items()),'shelf_service')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'shelf_service'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

from dq_check import named as _dq_named

def named(items, name):
    return _dq_named(items, name, error="named identity")

def require(good, marker):
    if not good:raise AssertionError(marker)

from dq_check import port_number as port_number

from dq_check import selector_matches as _dq_matches

def matches(selector, labels):
    return _dq_matches(labels, selector, dialect="policy_required")

from dq_check import selector_implies as implies

try:
    problems=[]
    def issue(marker, detail=''):
        problems.append(marker)
        print('Network policy result '+detail+': ✗ [DQ:'+marker+']')
    try:policies=get('networkpolicies')['items']
    except Exception:issue('policies');policies=[]
    try:clients=get('pods')['items']
    except Exception:issue('pods');clients=[]
    clients=[p for p in clients if p.get('metadata',{}).get('labels',{}).get('app')=='client']
    if not clients:
        if 'pods' not in problems:issue('pods')
        raise SystemExit(1)
    named_policies=[p for p in policies if p.get('metadata',{}).get('name')=='client-egress']
    if len(named_policies)!=1:
        issue('named');raise SystemExit(1)
    spec=named_policies[0]['spec']
    def flows(spec):
        result=set()
        for rule in spec.get('egress',[]):
            if not rule.get('to') or not rule.get('ports'):raise ValueError('unbounded egress')
            for peer in rule['to']:
                if set(peer)=={'namespaceSelector','podSelector'} and implies(peer['namespaceSelector'],{'kubernetes.io/metadata.name':'kube-system'}) and implies(peer['podSelector'],{'k8s-app':'kube-dns'}):target='dns'
                elif set(peer)=={'podSelector'} and implies(peer['podSelector'],{'app':'shelf'}):target='shelf'
                else:raise ValueError('unbounded peer')
                for p in rule['ports']:
                    protocol=p.get('protocol','TCP');value=p.get('port')
                    if target=='shelf' and isinstance(value,str) and value:
                        number=port_number(get('pod','shelf-0')['spec'].get('containers',[]),value,protocol)
                    else:number=value
                    if type(number) is not int or p.get('endPort',number)!=number:raise ValueError('port')
                    result.add((target,protocol,number))
        return result
    expected={('dns','UDP',53),('dns','TCP',53),('shelf','TCP',8080)}
    if 'Egress' not in spec.get('policyTypes',[]):issue('types')
    if not implies(spec.get('podSelector',{}),{'app':'client'}) or not all(matches(spec.get('podSelector',{}),p['metadata']['labels']) for p in clients):issue('selector')
    try:actual=flows(spec)
    except Exception:issue('egress')
    else:
        for target,protocol,port in sorted(expected-actual):issue('missing_'+target+'_'+protocol.lower()+'_'+str(port))
        for target,protocol,port in sorted(actual-expected):issue('unexpected',target+' '+protocol+' '+str(port))
    for other in policies:
        if other['metadata']['name']=='client-egress':continue
        spec=other['spec'];name=other['metadata']['name']
        try:
            if 'Egress' in spec.get('policyTypes',[]) and any(matches(spec.get('podSelector',{}),p['metadata']['labels']) for p in clients):
                if not flows(spec)<=expected:issue('other_egress',name)
        except Exception:issue('other_invalid',name)
    if problems:raise SystemExit(1)
except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'egress'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
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
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- nslookup -type=A "shelf-0.shelf.$DQ_NAMESPACE.svc.cluster.local." >/dev/null 2>&1; then
  printf '%s\n' 'deployment/client DNS shelf-0.shelf: ✗ [DQ:dns]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 3 http://shelf-0.shelf:8080 2>/dev/null)" = ledger-120; then
  printf '%s\n' 'deployment/client → shelf-0.shelf:8080 = ledger-120: ✗ [DQ:http]'
  failed=1
fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
