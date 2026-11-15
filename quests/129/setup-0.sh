set -euo pipefail
cd ~/quest
kubectl delete configmap station --wait=false
python3 -I - <<'DQ_RETIREMENT_SEED'
import base64,hashlib,json,os,subprocess
from pathlib import Path
def get(kind,name):
    return json.loads(subprocess.check_output(['kubectl','get',kind,name,'-o','json'],text=True))
def create(value):
    subprocess.run(['kubectl','create','-f','-'],input=json.dumps(value),text=True,check=True)
retired=get('secret','station-record')
old=json.loads(Path('cleanup-contract.json').read_text())
contract={'schema':1,'configurationFile':'/config/value','fingerprintURL':'http://127.0.0.1:8080',
          'successorKind':'Secret','parentLabel':'training.devops-quests.local/parent-uid',
          'preserveExistingConsumerDeployments':True,'preserveProvidedWorkerImages':True,
          'successorDataMatchesRetiringRecord':True,'successorIndependentOfRetiredParent':True,
          'currentReadyConsumers':1,'readonlySuccessorVolume':True,
          'observesCurrentStateOnly':True}
consumers={}
for name in ('dispatch','reporter'):
    worker={'name':'worker','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never',
            'command':['sh','-c',"mkdir -p /tmp/status; sha256sum /config/value | awk '{print $1}' > /tmp/status/index.html; exec httpd -f -p 8080 -h /tmp/status"],
            'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'cpu':'200m','memory':'32Mi'}},
            'securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},
            'volumeMounts':[{'name':'configuration','mountPath':'/config','readOnly':True}],
            'readinessProbe':{'httpGet':{'path':'/','port':8080},'periodSeconds':1,'failureThreshold':3}}
    pod={'automountServiceAccountToken':False,
         'securityContext':{'runAsNonRoot':True,'runAsUser':1000,'runAsGroup':1000,'fsGroup':1000,'seccompProfile':{'type':'RuntimeDefault'}},
         'containers':[worker],'volumes':[{'name':'configuration','secret':{'secretName':'station-record'}}],
         'terminationGracePeriodSeconds':1}
    create({'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':name},
            'spec':{'replicas':1,'selector':{'matchLabels':{'app':name}},
                    'template':{'metadata':{'labels':{'app':name}},'spec':pod}}})
    subprocess.run(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'],check=True)
    consumers[name]={'uid':get('deployment',name)['metadata']['uid'],'image':worker['image']}
facts={'contract':contract,'consumers':consumers,'retiredParentUID':old['parent_uid'],
       'retiredRecordUID':retired['metadata']['uid'],
       'dataHash':hashlib.sha256(json.dumps(retired['data'],sort_keys=True).encode()).hexdigest(),
       'fingerprint':hashlib.sha256(base64.b64decode(retired['data']['value'])).hexdigest()}
Path('retirement-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('retirement-identities.json').write_text(json.dumps(facts)+'\n')
DQ_RETIREMENT_SEED
