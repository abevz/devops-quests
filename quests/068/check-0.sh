set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" 'def same_dir($want): if type!="string" then false elif startswith("/") then false else (split("/") | map(select(.!="" and .!="."))) as $parts | ($parts | all(.!="..")) and ($parts | join("/")==$want) end; .spec.source.repoURL==$url and (.spec.source.path | same_dir("manifests")) and .spec.source.targetRevision=="main"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl get application board -o json | jq -e '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080)" = north-68
)
[ $? -eq 0 ] || failed=1
(
set -e
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" origin/main
test "$(git -C repository rev-parse origin/main)" != "$(cat /run/dq/facts/0/baseline-commit)"
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
python3 -I - <<'DQ_GIT_HEALTH'
import json,re,subprocess,sys,yaml
from pathlib import Path
from decimal import Decimal

def execute(args):return subprocess.check_output(args,stderr=subprocess.DEVNULL,timeout=4)
def deployment(text):
    found=[]
    def visit(value,depth=0):
        if depth>64:raise ValueError('manifest nesting')
        if isinstance(value,list):
            for entry in value:visit(entry,depth+1)
        elif isinstance(value,dict):
            if value.get('kind')=='List':visit(value.get('items',[]),depth+1)
            elif value.get('kind')=='Deployment' and value.get('metadata',{}).get('name')=='board':found.append(value)
    for value in yaml.safe_load_all(text):visit(value)
    if len(found)!=1:raise ValueError('board Deployment identity')
    return found[0]
def worker(document):
    values=[c for c in document['spec']['template']['spec']['containers'] if c.get('name')=='worker']
    if len(values)!=1:raise ValueError('application worker identity')
    return values[0]
def quantity(value):
    if isinstance(value,bool):raise ValueError('quantity')
    match=re.fullmatch(r'([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)([numkKMGTPE]|[KMGTPE]i)?',str(value))
    if not match:raise ValueError('quantity')
    scales={'n':Decimal('1e-9'),'u':Decimal('1e-6'),'m':Decimal('1e-3'),'k':Decimal('1e3'),'K':Decimal('1e3'),'M':Decimal('1e6'),'G':Decimal('1e9'),'T':Decimal('1e12'),'P':Decimal('1e15'),'E':Decimal('1e18')}
    suffix=match[2] or '';factor=Decimal(2)**(10*('KMGTPE'.index(suffix[0])+1)) if suffix.endswith('i') else scales.get(suffix,Decimal(1))
    amount=Decimal(match[1])*factor
    if not amount.is_finite():raise ValueError('quantity')
    return amount

def subset(reference,current,path=(),ignore_behavior=False):
    if path[-3:-1] in (('resources','requests'),('resources','limits')):
        try:return quantity(reference)==quantity(current)
        except Exception:return False
    if isinstance(reference,dict):
        if not isinstance(current,dict):return False
        for key,value in reference.items():
            if ignore_behavior and key in ('command','args','readinessProbe','livenessProbe','startupProbe'):continue
            if key not in current or not subset(value,current[key],path+(key,),ignore_behavior):return False
        return True
    if isinstance(reference,list):
        if not isinstance(current,list):return False
        if path[-1:] in (('drop',),):return set(reference)<=set(current)
        if all(isinstance(item,dict) and isinstance(item.get('name'),str) for item in reference):
            for item in reference:
                matches=[candidate for candidate in current if isinstance(candidate,dict) and candidate.get('name')==item['name']]
                if len(matches)!=1 or not subset(item,matches[0],path+(item['name'],),ignore_behavior):return False
            return True
        return reference==current
    return type(reference) is type(current) and reference==current

def port(value,container):
    if type(value) is int and 0<value<65536:return value
    if isinstance(value,str):
        values=[item.get('containerPort') for item in container.get('ports',[]) if item.get('name')==value]
        if len(values)==1 and type(values[0]) is int:return values[0]
    raise ValueError('health listener')
def probe(container,field='readinessProbe'):
    value=container.get(field)
    if value is None:return None
    handlers=[name for name in ('httpGet','tcpSocket','exec','grpc') if value.get(name) is not None]
    if len(handlers)!=1:raise ValueError('readiness handler')
    kind=handlers[0];handler=value[kind]
    if kind=='httpGet':request=(kind,handler.get('host') or '',handler.get('path') or '/',handler.get('scheme') or 'HTTP',port(handler['port'],container),tuple((h.get('name','').lower(),h.get('value','')) for h in handler.get('httpHeaders',[])))
    elif kind=='tcpSocket':request=(kind,handler.get('host') or '',port(handler['port'],container))
    elif kind=='exec':request=(kind,tuple(handler.get('command',[])))
    else:request=(kind,port(handler['port'],container),handler.get('service') or '')
    defaults={'initialDelaySeconds':0,'timeoutSeconds':1,'periodSeconds':10,'successThreshold':1,'failureThreshold':3}
    timing=tuple(value.get(key) or default for key,default in defaults.items())
    return request,timing

def env(values):
    result={}
    for entry in values or []:
        name=entry['name']
        if entry.get('valueFrom'):
            ref=entry['valueFrom']
            choices=[key for key in ('secretKeyRef','configMapKeyRef','fieldRef','resourceFieldRef') if ref.get(key) is not None]
            if len(choices)!=1:raise ValueError('environment reference')
            kind=choices[0];item=ref[kind]
            if kind in ('secretKeyRef','configMapKeyRef'):result[name]=(kind,item.get('name'),item.get('key'))
            elif kind=='fieldRef':result[name]=(kind,item.get('apiVersion') or 'v1',item.get('fieldPath'))
            else:result[name]=(kind,item.get('containerName') or '',item.get('resource'),quantity(item.get('divisor') or '1'))
        else:result[name]=('value',entry.get('value') or '')
    return result

def agreement(desired,live):
    left,right=worker(desired),worker(live)
    if left.get('image')!=right.get('image'):return False
    if (left.get('command') or [])!=(right.get('command') or []) or (left.get('args') or [])!=(right.get('args') or []):return False
    if env(left.get('env'))!=env(right.get('env')):return False
    return all(probe(left,field)==probe(right,field) for field in ('readinessProbe','livenessProbe','startupProbe'))

def safety(reference,current):
    old=reference['spec']['template']['spec'];new=current['spec']['template']['spec'];base=worker(reference);actual=worker(current)
    old_pod=old.get('securityContext',{});new_pod=new.get('securityContext',{})
    for field in ('runAsUser','runAsGroup','runAsNonRoot','seccompProfile'):
        expected=base.get('securityContext',{}).get(field,old_pod.get(field))
        observed=actual.get('securityContext',{}).get(field,new_pod.get(field))
        if expected is not None and expected!=observed:return False
    for field in ('hostNetwork','hostPID','hostIPC'):
        if bool(new.get(field))!=bool(old.get(field)):return False
    for container in new.get('containers',[])+new.get('initContainers',[]):
        context=container.get('securityContext',{})
        if context.get('privileged',False) or context.get('allowPrivilegeEscalation') is not False:return False
        if 'ALL' not in context.get('capabilities',{}).get('drop',[]) or context.get('capabilities',{}).get('add'):return False
        uid=context.get('runAsUser',new_pod.get('runAsUser'))
        nonroot=context.get('runAsNonRoot',new_pod.get('runAsNonRoot'))
        if uid==0 or not (nonroot is True or (type(uid) is int and uid>0)):return False
    return True

try:
    desired=deployment(execute(['git','-C','repository','show','origin/main:manifests/board.yaml']))
    live=json.loads(execute(['kubectl','get','deployment','board','-o','json']))
    assert agreement(desired,live)
    execute(['kubectl','rollout','status','deployment/board','--timeout=3s'])
    assert execute(['timeout','4s','kubectl','exec','--pod-running-timeout=2s','deployment/board','-c','worker','--','wget','-qO-','-T','3','http://board:8080']).rstrip(b'\n')==b'north-68'
except Exception:
    sys.exit(1)
DQ_GIT_HEALTH
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_5]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
