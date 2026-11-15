set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_STARTUP'
import copy,json,subprocess
from pathlib import Path
contract=json.loads(Path('startup-contract.json').read_text())
def cli(args):return subprocess.run(args,capture_output=True,text=True,check=True,timeout=120).stdout
def get(name):return json.loads(cli(['kubectl','get','deployment',name,'-o','json']))
def patch(name,spec):
    cli(['kubectl','patch','deployment',name,'--type=merge','-p',json.dumps({'spec':{'template':{'spec':spec}}})])
    cli(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'])
source_env=[{'name':key,'valueFrom':{'configMapKeyRef':{'name':contract['sourceConfigMap'],'key':key}}} for key in ['CACHE_MIB','CACHE_ID']]
stager=next(role for role in contract['roles'] if role.get('initializer'))
initializer=next(c for c in get(stager['deployment'])['spec']['template']['spec']['initContainers'] if c['name']==stager['initializer'])
producer=get(contract['producer'])
spec=copy.deepcopy(producer['spec']['template']['spec'])
spec['securityContext'].update(fsGroup=1000,runAsGroup=1000)
spec['terminationGracePeriodSeconds']=1
spec['volumes']=[{'name':'cache','emptyDir':{'medium':'Memory'}}]
worker=next(c for c in spec['containers'] if c['name']=='worker')
worker['resources']['limits']['memory']=contract['memory']['producerWorkerLimit']
worker['env']=source_env
worker['volumeMounts']=[{'name':'cache','mountPath':contract['memoryPath']}]
worker['command']=copy.deepcopy(initializer['command'])
worker['command'][-1]+='exec httpd -f -p 8080 -h '+contract['memoryPath']
worker['readinessProbe']={'httpGet':{'path':contract['metadataPath'],'port':8080},'periodSeconds':1}
patch(contract['producer'],spec)
for role in contract['roles']:
    name=role['deployment']
    if name==contract['producer']:continue
    spec=copy.deepcopy(get(name)['spec']['template']['spec'])
    if role.get('initializer'):
        next(c for c in spec['initContainers'] if c['name']==role['initializer'])['resources']['limits']['memory']='90Mi'
    else:
        next(c for c in spec['containers'] if c['name']=='worker')['env']=source_env
    patch(name,spec)
DQ_STARTUP
