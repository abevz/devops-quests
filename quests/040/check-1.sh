set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
kubectl rollout status deployment/board --timeout=3s
set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_BOSS'
import json, os, re, subprocess, sys
from pathlib import Path
from decimal import Decimal

def get(kind, name=None):
    args=['kubectl','get',kind]+([name] if name else [])+['-o','json']
    return json.loads(subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=3))

def scaled(value,count,up):
    if type(value) is int:
        if value<0:raise ValueError('budget')
        return value
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]+%',value):raise ValueError('budget')
    value=int(value[:-1])*count
    return (value+99)//100 if up else value//100

def require(good, marker):
    if not good:raise AssertionError(marker)

try:
    d=get('deployment','board');s=d['spec'];rolling=s.get('strategy',{}).get('rollingUpdate',{})
    require(s.get('replicas')==2 and d.get('status',{}).get('availableReplicas')==2,'available')
    require(s.get('strategy',{}).get('type')=='RollingUpdate' and scaled(rolling.get('maxSurge','25%'),2,True)==1 and scaled(rolling.get('maxUnavailable','25%'),2,False)==0,'strategy')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'strategy'
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

try:
    service=get('service','board')['spec'];d=get('deployment','board');labels=d['spec']['template']['metadata']['labels']
    selector=service.get('selector',{})
    require(selector.get('app')=='board' and all(labels.get(k)==v for k,v in selector.items()),'service')
    ports=[p for p in service.get('ports',[]) if p.get('port')==8080 and p.get('protocol','TCP')=='TCP']
    require(len(ports)==1 and port_number(d['spec']['template']['spec']['containers'],ports[0].get('targetPort',8080))==8080,'service')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'service'
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

def current_pods(deployment,replicasets,pods):
    uid=deployment['metadata']['uid']
    if not isinstance(uid,str) or not uid:raise ValueError('deployment identity')
    owners={rs['metadata']['uid'] for rs in replicasets.get('items',[]) if any(ref.get('kind')=='Deployment' and ref.get('uid')==uid and ref.get('controller') is True for ref in rs.get('metadata',{}).get('ownerReferences',[]))}
    return [pod for pod in pods.get('items',[]) if pod.get('metadata',{}).get('deletionTimestamp') is None and pod.get('status',{}).get('phase') not in ('Failed','Succeeded') and any(ref.get('kind')=='ReplicaSet' and ref.get('uid') in owners and ref.get('controller') is True for ref in pod.get('metadata',{}).get('ownerReferences',[]))]

try:
    d=get('deployment','board');pods=current_pods(d,get('replicasets'),get('pods'));pods=[p for p in pods if p.get('status',{}).get('phase')=='Running']
    require(bool(pods),'http')
    for pod in pods:
        value=subprocess.check_output(['kubectl','exec','--pod-running-timeout=2s',pod['metadata']['name'],'-c','worker','--','wget','-qO-','-T','3','http://board:8080'],stderr=subprocess.DEVNULL,timeout=4)
        require(value.rstrip(b'\n')==b'north-40','http')

except Exception as error:
    marker = str(error) if isinstance(error,AssertionError) and re.fullmatch(r'[a-z0-9_]+',str(error)) else 'http'
    print('Required result is missing: ✗ [DQ:'+marker+']')
    sys.exit(1)
DQ_BOSS
)
[ $? -eq 0 ] || failed=1
exit "$failed"
