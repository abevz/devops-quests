set -euo pipefail
cd ~/quest
python3 -I - <<'DQ_RELEASE_SEED'
import copy,json,os,secrets,subprocess,time,yaml
from pathlib import Path

previous=secrets.token_hex(16)
current=secrets.token_hex(16)
image=os.environ['DQ_APP_IMAGE']

def execute(args):
    return subprocess.run(args,capture_output=True,text=True,check=True,timeout=120).stdout

def write(path,value):
    Path(path).write_text(value)

def get(kind,name):
    return json.loads(execute(['kubectl','get',kind,name,'-o','json']))

def wait_record(service,expected):
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        result=subprocess.run(['kubectl','exec','deployment/relay','-c','worker','--','wget','-qO-','-T','3','http://'+service+':8080/release.json'],capture_output=True,text=True,timeout=10)
        try:
            if result.returncode==0 and json.loads(result.stdout)==expected:return
        except ValueError:pass
        time.sleep(.3)
    raise RuntimeError('The initial publication did not reach its native Service')

def chart(folder,values,resources):
    Path(folder+'/templates').mkdir(parents=True,exist_ok=True)
    write(folder+'/Chart.yaml','apiVersion: v2\nname: training-release\nversion: 0.1.0\n')
    write(folder+'/values.yaml',yaml.safe_dump(values,sort_keys=False))
    write(folder+'/templates/resources.yaml',resources)

def service(name,selector,legacy=False):
    ports=[{'name':'http','port':8080,'targetPort':'__TARGET__' if name=='board' else 8080}]
    if legacy:ports.append({'name':'previous','port':9090,'targetPort':'__TARGET__'})
    value={'apiVersion':'v1','kind':'Service','metadata':{'name':name},'spec':{'selector':{'app':selector},'ports':ports}}
    return yaml.safe_dump(value,sort_keys=False).replace('__TARGET__','{{ .Values.port }}')

producer=json.loads('{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": {"name": "relay"}, "spec": {"replicas": 1, "selector": {"matchLabels": {"app": "relay"}}, "template": {"metadata": {"labels": {"app": "relay"}}, "spec": {"securityContext": {"runAsNonRoot": true, "runAsUser": 1000, "seccompProfile": {"type": "RuntimeDefault"}}, "containers": [{"name": "worker", "image": "{{ .Values.image }}", "imagePullPolicy": "Never", "command": ["httpd", "-f", "-p", "{{ .Values.port }}", "-h", "/source"], "ports": [{"containerPort": 8080}], "resources": {"requests": {"cpu": "10m", "memory": "16Mi"}, "limits": {"memory": "64Mi"}}, "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}}, "volumeMounts": [{"name": "source", "mountPath": "/source", "readOnly": true}]}], "volumes": [{"name": "source", "configMap": {"name": "release-source"}}]}}}}')
deployment=yaml.safe_dump(producer,sort_keys=False)
bundle='apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: release-source\ndata:\n  index.html: "signalrail\\n"\n  release.json: {{ dict "publication_id" .Values.publicationId "route" "signalrail" | toJson | quote }}\n'
producer_values={'image':image,'port':9090,'publicationId':previous}
chart('chart',producer_values,deployment+'---\n'+bundle+'---\n'+service('board','relay',True))
execute(['helm','install','board','./chart','--wait','--timeout=90s'])
wait_record('board',{'publication_id':previous,'route':'signalrail'})
for name,port in [('dispatcher',9090),('archive',8080)]:
    consumer=copy.deepcopy(producer)
    consumer['metadata']['name']=name
    consumer['spec']['selector']['matchLabels']={'app':name}
    consumer['spec']['template']['metadata']['labels']={'app':name}
    spec=consumer['spec']['template']['spec']
    spec.pop('volumes')
    worker=spec['containers'][0]
    worker.pop('volumeMounts')
    worker['env']=[{'name':'UPSTREAM','value':'http://board:{{ .Values.upstreamPort }}/release.json'},{'name':'EXPECTED_PUBLICATION','value':'{{ .Values.expectedPublication }}'}]
    worker['command']=['sh','-c','mkdir -p /tmp/www; wget -qO /tmp/www/release.json "$UPSTREAM"; grep -Fq "\\"publication_id\\":\\"$EXPECTED_PUBLICATION\\"" /tmp/www/release.json || { echo "Startup publication mismatch" >&2; exit 1; }; echo "Cached source publication:"; cat /tmp/www/release.json; exec httpd -f -p 8080 -h /tmp/www']
    worker['readinessProbe']={'httpGet':{'path':'/release.json','port':8080},'periodSeconds':1}
    chart(name,{'image':image,'upstreamPort':8080,'expectedPublication':previous},yaml.safe_dump(consumer,sort_keys=False)+'---\n'+service(name,name))
    execute(['helm','install',name,'./'+name,'--set','upstreamPort='+str(port),'--set-string','expectedPublication='+previous,'--wait','--timeout=90s'])
    wait_record(name,{'publication_id':previous,'route':'signalrail'})

retained={kind+'/'+name:get(kind,name)['metadata']['uid'] for kind,name in [('deployment','relay'),('configmap','release-source'),('service','board'),('deployment','dispatcher'),('service','dispatcher'),('deployment','archive'),('service','archive')]}
producer_values.update(port=8080,publicationId=current)
write('chart/Chart.yaml','apiVersion: v2\nname: training-release\nversion: 0.2.0\n')
write('chart/values.yaml',yaml.safe_dump(producer_values,sort_keys=False))
write('chart/templates/resources.yaml',deployment+'---\n'+bundle+'---\n'+service('board','relay'))
execute(['helm','upgrade','board','./chart','--reuse-values','--set','port=bad-port','--set-string','publicationId='+current])
for name in ['dispatcher','archive']:
    write(name+'/Chart.yaml','apiVersion: v2\nname: training-release\nversion: 0.2.0\n')
    write(name+'/values.yaml',yaml.safe_dump({'image':image,'upstreamPort':8080,'expectedPublication':current},sort_keys=False))
contract={'producer':{'release':'board','deployment':'relay','service':'board','configMap':'release-source','chart':'chart'},'consumers':[{'release':name,'deployment':name,'service':name,'chart':name} for name in ['dispatcher','archive']],'servicePort':8080,'response':'signalrail','metadataPath':'/release.json','publicationSchema':{'publication_id':'string','route':'string'}}
write('release-contract.json',json.dumps(contract,indent=2)+'\n')
facts={'contract':contract,'identities':retained,'image':image,'data':get('configmap','release-source')['data'],'publication':{'publication_id':current,'route':'signalrail'}}
write('release-identities.json',json.dumps(facts,indent=2)+'\n')
DQ_RELEASE_SEED
