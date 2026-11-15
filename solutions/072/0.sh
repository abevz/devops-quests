set -euo pipefail
cd ~/quest
kubectl patch job importer --type=merge -p '{"spec":{"backoffLimit":1,"activeDeadlineSeconds":30}}'
kubectl wait --for=condition=Failed job/importer --timeout=60s
python3 -I - <<'DQ_RECURRING_REFERENCE'
import copy,json,subprocess,time
from pathlib import Path
contract=json.loads(Path('batch-contract.json').read_text())
def get(kind,name=''):
    return json.loads(subprocess.check_output(['kubectl','get',kind]+([name] if name else [])+['-o','json'],text=True,timeout=10))
job=get('job',contract['currentJob'])
spec={k:copy.deepcopy(job['spec'][k]) for k in ('backoffLimit','activeDeadlineSeconds','parallelism','completions','template')}
spec['template']['metadata']={'labels':{'app':'recurring-validator'}}
cron={'apiVersion':'batch/v1','kind':'CronJob','metadata':{'name':contract['recurringValidator']},'spec':{'schedule':contract['schedule'],'suspend':False,'concurrencyPolicy':'Forbid','failedJobsHistoryLimit':2,'jobTemplate':{'spec':spec}}}
subprocess.run(['kubectl','apply','-f','-'],input=json.dumps(cron),text=True,check=True,timeout=15)
uid=get('cronjob',contract['recurringValidator'])['metadata']['uid']
deadline=time.monotonic()+140
while time.monotonic()<deadline:
    for child in get('jobs')['items']:
        owned=any(o.get('uid')==uid and o.get('kind')=='CronJob' and o.get('controller') is True for o in child['metadata'].get('ownerReferences',[]))
        failed=any(c.get('type')=='Failed' and c.get('status')=='True' for c in child.get('status',{}).get('conditions',[]))
        if owned and failed and child['spec'].get('backoffLimit')==1 and child['spec'].get('activeDeadlineSeconds')==30:
            raise SystemExit(0)
    time.sleep(2)
raise SystemExit('No bounded failed scheduled execution observed')
DQ_RECURRING_REFERENCE
