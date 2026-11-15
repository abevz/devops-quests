set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_LOAD_REFERENCE'
import json,subprocess,time
from pathlib import Path
contract=json.loads(Path('autoscaling-contract.json').read_text())
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True,timeout=10))
def patch(kind,name,value):
    subprocess.run(['kubectl','patch',kind,name,'--type=merge','-p',json.dumps(value)],check=True,timeout=15)
patch('hpa',contract['hpa'],{'spec':{'scaleTargetRef':{'apiVersion':'apps/v1','kind':'Deployment','name':contract['server']}}})
server=get('deployment',contract['server'])
worker=next(c for c in server['spec']['template']['spec']['containers'] if c['name']=='worker')
worker['resources']['requests']['cpu']=contract['cpu']['request']
worker['resources']['limits']['cpu']=contract['cpu']['limit']
patch('deployment',contract['server'],{'spec':{'template':{'spec':{'containers':server['spec']['template']['spec']['containers']}}}})
client=get('deployment',contract['client'])
worker=next(c for c in client['spec']['template']['spec']['containers'] if c['name']=='worker')
url='http://'+contract['server']+':'+str(contract['port'])+contract['handler']['endpoint']
worker['command']=['sh','-c','work() { while :; do wget -qO- -T 10 "$WORK_URL" >/dev/null || sleep 1; done; }; work & work & work & wait']
worker['env']=[{'name':'WORK_URL','value':url}]
patch('deployment',contract['client'],{'spec':{'template':{'spec':{'containers':client['spec']['template']['spec']['containers']}}}})
for name in (contract['server'],contract['client']):
    subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
deadline=time.monotonic()+180
stable=0
while time.monotonic()<deadline:
    hpa=get('hpa',contract['hpa']);server=get('deployment',contract['server']);status=hpa.get('status',{})
    utilization=next((m.get('resource',{}).get('current',{}).get('averageUtilization',0) for m in status.get('currentMetrics',[]) if m.get('resource',{}).get('name')=='cpu'),0)
    if (status.get('currentReplicas')==2 and status.get('desiredReplicas')==2 and utilization>50
            and server.get('status',{}).get('readyReplicas')==2
            and any(c.get('type')=='ScalingActive' and c.get('status')=='True' for c in status.get('conditions',[]))):
        stable+=1
        if stable>=3:
            raise SystemExit(0)
    else:
        stable=0
    time.sleep(2)
raise SystemExit('No active two-replica demand response observed')
DQ_LOAD_REFERENCE
