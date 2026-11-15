set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_STORAGE_REFERENCE'
import copy,json,os,subprocess
from pathlib import Path
def cli(args):
    return subprocess.run(args,check=True,capture_output=True,text=True,timeout=100).stdout
def get(kind,name):
    return json.loads(cli(['kubectl','get',kind,name,'-o','json']))
def create(obj):
    return json.loads(subprocess.run(['kubectl','create','-f','-','-o','json'],input=json.dumps(obj),check=True,capture_output=True,text=True,timeout=30).stdout)
contract=json.loads(Path('storage-contract.json').read_text());source=contract['source'];target=contract['target'];claim=get('pvc',target['claim']);origin=get('pvc',source['claim'])
if claim.get('status',{}).get('phase') != 'Bound':
    if claim.get('spec',{}).get('volumeName'):raise RuntimeError('Refusing to discard a claim with an assigned volume')
    cli(['kubectl','scale','deployment/'+target['deployment'],'--replicas=0'])
    cli(['kubectl','delete','pvc',target['claim'],'--wait=true'])
    create({'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':target['claim']},'spec':{'accessModes':claim['spec']['accessModes'],'storageClassName':origin['spec']['storageClassName'],'resources':{'requests':{'storage':claim['spec']['resources']['requests']['storage']}}}})
cli(['kubectl','scale','deployment/'+target['deployment'],'--replicas=1'])
cli(['kubectl','rollout','status','deployment/'+target['deployment'],'--timeout=90s'])
security={'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}}
pod={'restartPolicy':'Never','automountServiceAccountToken':False,'securityContext':{'runAsNonRoot':True,'runAsUser':1000,'runAsGroup':1000,'fsGroup':1000,'seccompProfile':{'type':'RuntimeDefault'}},'containers':[{'name':'worker','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never','command':['sh','-c','rm -f /target/index.html /target/payload.bin; cp /source/index.html /target/index.html; cp /source/payload.bin /target/payload.bin'],'securityContext':security,'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'cpu':'100m','memory':'32Mi'}},'volumeMounts':[{'name':'source','mountPath':'/source','readOnly':True},{'name':'target','mountPath':'/target'}]}],'volumes':[{'name':'source','persistentVolumeClaim':{'claimName':source['claim']}},{'name':'target','persistentVolumeClaim':{'claimName':target['claim']}}]}
job=create({'apiVersion':'batch/v1','kind':'Job','metadata':{'generateName':'recover-'},'spec':{'backoffLimit':0,'activeDeadlineSeconds':60,'template':{'spec':pod}}})
cli(['kubectl','wait','--for=condition=Complete','job/'+job['metadata']['name'],'--timeout=90s'])
DQ_STORAGE_REFERENCE
