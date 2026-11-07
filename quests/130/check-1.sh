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

def named(items, name):
    found=[x for x in items or [] if isinstance(x,dict) and x.get('name')==name]
    if len(found)!=1:raise ValueError('named identity')
    return found[0]

def worker(document):return named(document['spec']['template']['spec']['containers'],'worker')

def quantity(value):
    if isinstance(value,bool):raise ValueError('quantity')
    match=re.fullmatch(r'([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)([numkKMGTPE]|[KMGTPE]i)?',str(value))
    if not match:raise ValueError('quantity')
    suffix=match[2] or ''
    factors={'':1,'n':Decimal('1e-9'),'u':Decimal('1e-6'),'m':Decimal('1e-3'),'k':1000,'K':1000}
    for i,s in enumerate('MGTPE',2):factors[s]=1000**i
    for i,s in enumerate('KMGTPE',1):factors[s+'i']=1024**i
    return Decimal(match[1])*factors[suffix]

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    try:d=get('deployment','board')
    except Exception:d={}
    try:resources=worker(d).get('resources',{})
    except Exception:resources={}
    try:request=quantity(resources.get('requests',{}).get('cpu','0'))
    except Exception:request=None
    try:limit=quantity(resources.get('limits',{}).get('cpu','0'))
    except Exception:limit=None
    checks=[('request',request is not None and request>0 and limit is not None and request<=limit),('limit',limit is not None and 0<limit<=Decimal('0.2')),('ready',d.get('status',{}).get('readyReplicas')==2)]
    failed=False
    for marker,good in checks:
        if not good:print('Required scaling result is missing: ✗ [DQ:'+marker+']');failed=True
    if failed:raise SystemExit(1)
except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'request'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
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
    try:d=get('hpa','board')
    except Exception:d={}
    spec=d.get('spec',{});status=d.get('status',{});target=spec.get('scaleTargetRef',{})
    metrics=[m.get('resource',{}) for m in spec.get('metrics',[]) if m.get('type')=='Resource' and m.get('resource',{}).get('name')=='cpu']
    checks=[('minimum',spec.get('minReplicas',1)==1 and bool(spec)),('maximum',spec.get('maxReplicas')==2),('target',target.get('apiVersion')=='apps/v1' and target.get('kind')=='Deployment' and target.get('name')=='board' and len(metrics)==1 and metrics[0].get('target',{}).get('type')=='Utilization' and metrics[0]['target'].get('averageUtilization')==50),('current',status.get('currentReplicas')==2),('desired',status.get('desiredReplicas')==2),('metric',any(m.get('type')=='Resource' and m.get('resource',{}).get('name')=='cpu' and type(m['resource'].get('current',{}).get('averageUtilization')) is int and m['resource']['current']['averageUtilization']>50 for m in status.get('currentMetrics',[])))]
    failed=False
    for marker,good in checks:
        if not good:print('Required scaling result is missing: ✗ [DQ:'+marker+']');failed=True
    if failed:raise SystemExit(1)
except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'target'
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
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
class=$(jq -r '.class // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
gateway=$(timeout 2s kubectl get gateway station -o json 2>/dev/null || true)
if ! test -n "$class" || ! jq -e --arg class "$class" '.spec.gatewayClassName==$class' <<<"$gateway" >/dev/null 2>&1; then printf '%s\n' 'gateway class = gateway-target.json class: ✗ [DQ:gateway_class]'; failed=1; fi
check gateway_accepted 'gateway Accepted = True' 'any(.status.conditions[]?;.type=="Accepted" and .status=="True")' "$gateway"
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
    try:route=get('httproute','board');service=get('service','board')
    except Exception:
        print('Route backend is unavailable: ✗ [DQ:backend]')
        print('Route references are unavailable: ✗ [DQ:resolved]')
        raise SystemExit(1)
    ports={p['port'] for p in service['spec'].get('ports',[]) if p.get('protocol','TCP')=='TCP'}
    # Bind static routing to the same supplied Host and URL as the HTTP probe.
    from urllib.parse import urlsplit, parse_qs
    target=json.loads(Path('/run/dq/facts/0/gateway-target.json').read_text())
    url=urlsplit(target.get('url','http://gateway/'));request_path=url.path or '/';query=parse_qs(url.query)
    host='north.station.internal'
    hostnames=route['spec'].get('hostnames',[])
    require(not hostnames or any(h==host or h.startswith('*.') and host.endswith(h[1:]) for h in hostnames),'backend')
    candidates=[]
    for order,rule in enumerate(route['spec'].get('rules',[])):
        for match in rule.get('matches',[{}]):
            if match.get('method','GET')!='GET':continue
            path=match.get('path',{'type':'PathPrefix','value':'/'});kind=path.get('type','PathPrefix');value=path.get('value','/')
            if kind=='Exact' and request_path!=value:continue
            if kind=='PathPrefix' and not (request_path==value or request_path.startswith(value.rstrip('/')+'/')):continue
            headers=match.get('headers',[])
            if any(h.get('name','').lower()=='host' and h.get('type','Exact')=='Exact' and h.get('value')!=host for h in headers):continue
            params=match.get('queryParams',[])
            if any(p.get('type','Exact')=='Exact' and p.get('value') not in query.get(p.get('name'),[]) for p in params):continue
            # Unknown regex/header semantics are treated conservatively as
            # potentially matching; an unrelated simple path is excluded.
            rank=(2 if kind=='Exact' else 1,len(value),bool(match.get('method')),len(headers),len(params))
            candidates.append((rank,order,rule))
    require(bool(candidates),'backend')
    best=max(rank for rank,_,_ in candidates)
    matching=[r for rank,_,r in candidates if rank==best]
    active=[b for r in matching for b in r.get('backendRefs',[]) if b.get('weight',1)>0]
    require(bool(active) and all(b.get('name')=='board' and b.get('kind','Service')=='Service' and b.get('group','')=='' and b.get('namespace',os.environ['DQ_NAMESPACE'])==os.environ['DQ_NAMESPACE'] and b.get('port') in ports for b in active),'backend')
    require(any(any(c.get('type')=='ResolvedRefs' and c.get('status')=='True' for c in p.get('conditions',[])) for p in route.get('status',{}).get('parents',[])),'resolved')

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
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def require(good, marker):
    if not good:raise AssertionError(marker)

def port_number(containers, value, protocol='TCP'):
    if type(value) is int:return value
    if not isinstance(value,str) or not value:raise ValueError('named port')
    found={p['containerPort'] for c in containers for p in c.get('ports',[]) if p.get('name')==value and p.get('protocol','TCP')==protocol}
    if len(found)!=1:raise ValueError('named port')
    return found.pop()

def matches(selector, labels):
    if not isinstance(selector,dict) or set(selector)-{'matchLabels','matchExpressions'}:raise ValueError('selector')
    if any(labels.get(k)!=v for k,v in selector.get('matchLabels',{}).items()):return False
    for e in selector.get('matchExpressions',[]):
        k,op,values=e['key'],e['operator'],e.get('values',[])
        if op=='In':good=k in labels and labels[k] in values
        elif op=='NotIn':good=k not in labels or labels[k] not in values
        elif op=='Exists':good=k in labels
        elif op=='DoesNotExist':good=k not in labels
        else:raise ValueError('selector operator')
        if not good:return False
    return True

def implies(selector, required):
    # Prove both the required identities and satisfiability of conjunctions.
    if not isinstance(selector,dict) or set(selector)-{'matchLabels','matchExpressions'}:return False
    allowed={k:{v} for k,v in selector.get('matchLabels',{}).items()}
    present=set(allowed);absent=set();excluded={}
    for e in selector.get('matchExpressions',[]):
        k,op,vs=e.get('key'),e.get('operator'),set(e.get('values',[]))
        if op=='In':
            present.add(k);allowed[k]=allowed.get(k,vs)&vs
        elif op=='NotIn':excluded.setdefault(k,set()).update(vs)
        elif op=='DoesNotExist':absent.add(k)
        elif op=='Exists':present.add(k)
        else:return False
    if present&absent:return False
    for k in allowed:allowed[k]-=excluded.get(k,set())
    return all(allowed.get(k)=={v} for k,v in required.items()) and all(v for v in allowed.values())

try:
    policy=get('networkpolicy','board-ingress')['spec'];target=json.loads(Path('/run/dq/facts/0/gateway-target.json').read_text());deployment=get('deployment','board')
    labels=deployment['spec']['template']['metadata']['labels'];require(implies(policy.get('podSelector',{}),{'app':'board'}) and matches(policy.get('podSelector',{}),labels),'policy')
    require('Ingress' in policy.get('policyTypes',[]),'policy');flows=set()
    for rule in policy.get('ingress',[]):
        require(bool(rule.get('from')) and bool(rule.get('ports')),'policy')
        for peer in rule['from']:
            require(set(peer)=={'namespaceSelector','podSelector'} and implies(peer['namespaceSelector'],{'kubernetes.io/metadata.name':target['namespace']}) and implies(peer['podSelector'],{'app':'gateway'}),'policy')
        for p in rule['ports']:
            protocol=p.get('protocol','TCP');number=port_number(deployment['spec']['template']['spec']['containers'],p.get('port'),protocol)
            require(p.get('endPort',number)==number,'policy');flows.add((protocol,number))
    require(flows=={('TCP',8080)},'policy')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'policy'
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
check() { local id=$1 label=$2 expression=$3 document=$4; if ! jq -e "$expression" <<<"$document" >/dev/null 2>&1; then printf '%s\n' "$label: ✗ [DQ:$id]"; failed=1; fi; }
url=$(jq -r '.url // ""' /run/dq/facts/0/gateway-target.json 2>/dev/null || true)
if ! test -n "$url" || ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 3 --header='Host: north.station.internal' "$url" 2>/dev/null)" = north-130; then printf '%s\n' 'gateway north.station.internal = north-130: ✗ [DQ:gateway_http]'; failed=1; fi
if timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 2 http://board:8080 >/dev/null 2>&1; then printf '%s\n' 'direct board:8080 request fails: ✗ [DQ:direct_denied]'; failed=1; fi
if ! test -n "$url" || timeout 4s kubectl exec --pod-running-timeout=2s deployment/client -c worker -- wget -qO- -T 2 --header='Host: closed.station.internal' "$url" >/dev/null 2>&1; then printf '%s\n' 'gateway closed.station.internal request fails: ✗ [DQ:wrong_host]'; failed=1; fi
exit "$failed"
)
[ $? -eq 0 ] || failed=1
exit "$failed"
