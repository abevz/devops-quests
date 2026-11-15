set -euo pipefail
cd ~/quest
cat > board.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: board
spec:
  replicas: 1
  selector:
    matchLabels:
      app: board
  template:
    metadata:
      labels:
        app: board
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      terminationGracePeriodSeconds: 1
      containers:
      - name: worker
        image: __DQ_APP_IMAGE__
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - mkdir -p /tmp/site; printf "%s\n" "north-94" > /tmp/site/index.html; while :; do :; done & exec
          httpd -f -p 8080 -h /tmp/site
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          periodSeconds: 1
        resources:
          requests:
            cpu: 50m
            memory: 8Mi
          limits:
            cpu: 50m
            memory: 32Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
DQ_ASSET
python3 - board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.yaml
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: board
spec:
  selector:
    app: board
  ports:
  - name: http
    port: 8080
    targetPort: 8080
DQ_ASSET
python3 - service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.yaml
cat > measure.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
pod=$(kubectl get pods -l app=board -o json | jq -er '[.items[]|select(.metadata.deletionTimestamp==null)][0].metadata.name')
# Read within one exec: launching a separate reader spends this container's CPU quota.
kubectl exec "$pod" -- sh -c '
read_counter() {
 while read -r key value rest; do
  if test "$key" = nr_throttled; then printf "%s\n" "$value"; return; fi
 done < /sys/fs/cgroup/cpu.stat
 return 1
}
before=$(read_counter)
sleep 2
after=$(read_counter)
printf "%s\n" "$((after-before))"
'
DQ_ASSET
kubectl rollout status deployment/board --timeout=60s
bash measure.sh > initial-throttled
test "$(cat initial-throttled)" -ge 10

python3 -I - <<'DQ_DEMAND'
import copy,json,secrets,subprocess,yaml
from pathlib import Path
from dq_check import workload_worker

def command(args):
    return subprocess.run(args,capture_output=True,text=True,check=True,timeout=120).stdout

def get(kind,name):
    return json.loads(command(['kubectl','get',kind,name,'-o','json']))

def apply(value):
    subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(value),capture_output=True,text=True,check=True,timeout=60)

board=get('deployment','board')
identity=secrets.token_hex(16)
policy={'POLL_DELAY':'1','POLICY_ID':identity}
apply({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'poll-policy'},'data':policy})
poller='set -eu\nmkdir -p /tmp/progress\nn=0\nprintf \'{"sequence":0,"route":"north-94","delay":"%s","policy_id":"%s"}\\n\' "$POLL_DELAY" "$POLICY_ID" > /tmp/progress/progress.json\nhttpd -f -p 8080 -h /tmp/progress &\nwhile :; do\n response=$(wget -qO- -T 3 http://board:8080 || true)\n if test "$response" = north-94; then\n  n=$((n+1))\n  printf \'{"sequence":%s,"route":"%s","delay":"%s","policy_id":"%s"}\\n\' "$n" "$response" "$POLL_DELAY" "$POLICY_ID" > /tmp/progress/next.json\n  mv /tmp/progress/next.json /tmp/progress/progress.json\n fi\n sleep "$POLL_DELAY"\ndone'
for name in ['scan-a','scan-b']:
    consumer={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':name},'spec':copy.deepcopy(board['spec'])}
    consumer['spec']['selector']['matchLabels']={'app':name}
    consumer['spec']['template']['metadata']['labels']={'app':name}
    worker=consumer['spec']['template']['spec']['containers'][0]
    worker['command']=['sh','-c',poller]
    worker['env']=[{'name':'POLL_DELAY','value':'0'},{'name':'POLICY_ID','value':identity}]
    worker['resources']={'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'cpu':'500m','memory':'32Mi'}}
    worker['readinessProbe']={'httpGet':{'path':'/progress.json','port':8080},'periodSeconds':1}
    apply(consumer)
    apply({'apiVersion':'v1','kind':'Service','metadata':{'name':name},'spec':{'selector':{'app':name},'ports':[{'port':8080,'targetPort':8080}]}})
    command(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'])
contract={'producer':{'deployment':'board','service':'board','response':'north-94'},'consumers':[{'deployment':name,'service':name,'replicas':1} for name in ['scan-a','scan-b']],'policyConfigMap':'poll-policy','consumerEnvironment':['POLL_DELAY','POLICY_ID'],'servicePort':8080,'serviceType':'ClusterIP','progressPath':'/progress.json','progressSchema':{'sequence':{'type':'integer','minimum':0},'route':'string','delay':'string','policy_id':'string'},'measurement':{'metric':'nr_throttled','pauseSeconds':2,'maxIncrease':5,'container':'worker','file':'/sys/fs/cgroup/cpu.stat'},'worksheet':'measure.sh'}
identities={kind+'/'+name:get(kind,name)['metadata']['uid'] for kind,name in [('deployment','board'),('service','board'),('configmap','poll-policy'),('deployment','scan-a'),('service','scan-a'),('deployment','scan-b'),('service','scan-b')]}
facts={'contract':contract,'identities':identities,'image':workload_worker(board)['image'],'policy':policy}
Path('performance-contract.json').write_text(json.dumps(contract,indent=2)+'\n')
Path('performance-identities.json').write_text(json.dumps(facts,indent=2)+'\n')
DQ_DEMAND
rm board.yaml service.yaml measure.sh
