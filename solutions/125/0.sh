set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_AUTHORITY_REFERENCE'
import json,os,subprocess
from pathlib import Path
contract=json.loads(Path('authority-contract.json').read_text());ns=os.environ['DQ_NAMESPACE']
def apply(value):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),text=True,check=True)
def role(name,record):
    apply({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'Role','metadata':{'name':name},'rules':[{'apiGroups':[''],'resources':['configmaps'],'resourceNames':[record],'verbs':['get']}]})
def binding(name,role_name,account):
    apply({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'RoleBinding','metadata':{'name':name},'roleRef':{'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':role_name},'subjects':[{'kind':'ServiceAccount','name':account,'namespace':ns}]})
role('station-reader',contract['control']['configMap'])
binding('station-reader','station-reader',contract['control']['serviceAccount'])
for consumer in contract['consumers']:
    account=consumer['deployment']+'-access';role_name=consumer['deployment']+'-reader'
    apply({'apiVersion':'v1','kind':'ServiceAccount','metadata':{'name':account},'automountServiceAccountToken':False})
    role(role_name,consumer['configMap']);binding(role_name,role_name,account)
    patch={'spec':{'template':{'spec':{'serviceAccountName':account,'automountServiceAccountToken':False}}}}
    subprocess.run(['kubectl','patch','deployment',consumer['deployment'],'--type=merge','-p',json.dumps(patch)],check=True)
for consumer in contract['consumers']:
    subprocess.run(['kubectl','rollout','status','deployment/'+consumer['deployment'],'--timeout=90s'],check=True)
DQ_AUTHORITY_REFERENCE
