set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
printf '%s\n' "$PRIVATE_IMAGE" > release-image
# An independent artifact must survive; it cannot supply the lost release bytes.
mkdir -p protected-context
printf '%s\n' unrelated-cargo > protected-context/cargo
cat > protected-context/Dockerfile <<'BUILD'
FROM scratch
COPY cargo /cargo
LABEL purpose=protected-cargo
BUILD
docker build -t "$REGISTRY/protected:1" protected-context
docker push "$REGISTRY/protected:1"
docker image inspect "$REGISTRY/protected:1" --format '{{json .RepoDigests}}' | jq -er --arg p "$REGISTRY/protected@" '.[]|select(startswith($p))' > protected-image
rm -rf protected-context
docker save "$REGISTRY/parcel:1" -o recovery-image.tar
sha256sum recovery-image.tar | cut -d' ' -f1 > archive.sha256
kubectl create secret docker-registry registry-pull --docker-server="$REGISTRY" --docker-username="$REGISTRY_USER" --docker-password="$REGISTRY_PASSWORD"
python3 - <<'CONSUMERS'
import os,yaml
from pathlib import Path
image=os.environ['REGISTRY']+'/parcel:retired'
security={'runAsNonRoot':True,'runAsUser':1000,'seccompProfile':{'type':'RuntimeDefault'}}
worker={'name':'worker','image':image,'imagePullPolicy':'Always','securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'memory':'32Mi'}}}
pod={'securityContext':security,'imagePullSecrets':[{'name':'registry-pull'}],'containers':[worker]}
worker['command']=['sh','-c','mkdir -p /tmp/site; echo archive-97 >/tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site']
worker['ports']=[{'containerPort':8080}]
worker['readinessProbe']={'httpGet':{'path':'/','port':8080},'periodSeconds':2}
deployment={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'archive-web'},'spec':{'replicas':1,'selector':{'matchLabels':{'app':'archive-web'}},'template':{'metadata':{'labels':{'app':'archive-web'}},'spec':pod}}}
service={'apiVersion':'v1','kind':'Service','metadata':{'name':'archive-web'},'spec':{'selector':{'app':'archive-web'},'ports':[{'port':8080,'targetPort':8080}]}}
folder=Path('repository/manifests');folder.mkdir(parents=True)
(folder/'web.yaml').write_text(yaml.safe_dump_all([deployment,service],sort_keys=False))
# Copy before changing the independent batch program.
pod=yaml.safe_load(yaml.safe_dump(pod));pod['restartPolicy']='Never';worker=pod['containers'][0]
worker.pop('ports');worker.pop('readinessProbe');worker['command']=['sh','-c','echo checked-97']
cron={'apiVersion':'batch/v1','kind':'CronJob','metadata':{'name':'archive-scan'},'spec':{'schedule':'0 * * * *','suspend':True,'jobTemplate':{'spec':{'backoffLimit':0,'template':{'spec':pod}}}}}
Path('batch.yaml').write_text(yaml.safe_dump(cron,sort_keys=False))
app={'apiVersion':'argoproj.io/v1alpha1','kind':'Application','metadata':{'name':'release'},'spec':{'project':'station','source':{'repoURL':os.environ['GIT_URL'],'path':'manifests','targetRevision':'main'},'destination':{'server':'https://kubernetes.default.svc','namespace':os.environ['DQ_NAMESPACE']},'syncPolicy':{'automated':{'prune':True,'selfHeal':True}}}}
Path('application.yaml').write_text(yaml.safe_dump(app,sort_keys=False))
CONSUMERS
git -C repository add manifests
git -C repository commit -m 'Declare release consumers'
git -C repository push origin main
kubectl apply -f batch.yaml
kubectl create job --from=cronjob/archive-scan interrupted-attempt
kubectl apply -f application.yaml
for i in $(seq 1 90); do
 if kubectl get application release -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null; then break; fi
 sleep 1
done
kubectl get application release -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null
for i in $(seq 1 60); do
 if kubectl get pods -o json | jq -e '[.items[]|select(any(.status.containerStatuses[]?;.state.waiting.reason=="ErrImagePull" or .state.waiting.reason=="ImagePullBackOff"))]|length>=2' >/dev/null; then break; fi
 sleep 1
done
kubectl get pods -o json | jq -e '[.items[]|select(any(.status.containerStatuses[]?;.state.waiting.reason=="ErrImagePull" or .state.waiting.reason=="ImagePullBackOff"))]|length>=2' >/dev/null
kubectl get deployment,service,cronjob,job,application -o json > initial-consumers.json
python3 - <<'BASELINE'
import json
from pathlib import Path
items=json.loads(Path('initial-consumers.json').read_text())['items']
objects={o['kind']+'/'+o['metadata']['name']:o for o in items}
baseline={'identities':{k:o['metadata']['uid'] for k,o in objects.items() if o['kind']!='Job'},'source':objects['Application/release']['spec']['source'],'previous_jobs':[o['metadata']['uid'] for o in items if o['kind']=='Job'],'protected_image':Path('protected-image').read_text().strip(),'protected_tag':'1','http_response':'archive-97','batch_response':'checked-97'}
assert baseline['previous_jobs']
Path('recovery-baseline.json').write_text(json.dumps(baseline,indent=2)+'\n')
BASELINE
rm initial-consumers.json
# Delete every usable exact alias from this fresh private daemon, never the host.
image_id=$(docker image inspect "$REGISTRY/parcel:1" --format '{{.Id}}')
docker image rm --force "$image_id"
if docker image inspect "$PRIVATE_IMAGE" >/dev/null 2>&1; then exit 1; fi
if docker image inspect "$REGISTRY/parcel:1" >/dev/null 2>&1; then exit 1; fi
digest=${PRIVATE_IMAGE##*@}
curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -X DELETE "https://$REGISTRY/v2/parcel/manifests/$digest"
test "$(curl -sS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -o /dev/null -w '%{http_code}' "https://$REGISTRY/v2/parcel/manifests/$digest")" = 404
