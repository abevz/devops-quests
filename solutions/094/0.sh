set -euo pipefail
cd ~/quest
kubectl patch deployment board --type=json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/command", "value": ["sh", "-c", "mkdir -p /tmp/site; printf \"%s\\n\" \"north-94\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"]}]'
kubectl rollout status deployment/board --timeout=60s
python3 -I - <<'DQ_CONSUMERS'
import json,subprocess,time
from pathlib import Path
contract=json.loads(Path('performance-contract.json').read_text())
def cli(args,check=True):
    return subprocess.run(args,capture_output=True,text=True,check=check,timeout=100)
policy=json.loads(cli(['kubectl','get','configmap',contract['policyConfigMap'],'-o','json']).stdout)['data']
for consumer in contract['consumers']:
    name=consumer['deployment']
    deployment=json.loads(cli(['kubectl','get','deployment',name,'-o','json']).stdout)
    selector=','.join(k+'='+v for k,v in deployment['spec']['selector']['matchLabels'].items())
    before=json.loads(cli(['kubectl','get','pods','-l',selector,'-o','json']).stdout)['items']
    cli(['kubectl','set','env','deployment/'+name,'--from=configmap/'+contract['policyConfigMap']])
    updated=json.loads(cli(['kubectl','get','deployment',name,'-o','json']).stdout)
    cli(['kubectl','rollout','status','deployment/'+name,'--timeout=90s'])
    if updated['spec']['template'] != deployment['spec']['template']:
        for pod in before:
            cli(['kubectl','wait','--for=delete','pod/'+pod['metadata']['name'],'--timeout=30s'])
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        result=cli(['kubectl','exec','deployment/'+contract['producer']['deployment'],'-c','worker','--','wget','-qO-','-T','3','http://'+consumer['service']+':'+str(contract['servicePort'])+contract['progressPath']],False)
        try:
            record=json.loads(result.stdout)
            if result.returncode==0 and all(record[k]==policy[v] for k,v in [('delay','POLL_DELAY'),('policy_id','POLICY_ID')]):break
        except (ValueError,KeyError):pass
        time.sleep(.2)
    else:raise RuntimeError('Consumer did not adopt current inputs')
DQ_CONSUMERS
cat > measure.sh <<'DQ_WORKSHEET'
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
DQ_WORKSHEET
bash measure.sh
