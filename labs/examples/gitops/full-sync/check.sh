#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
source "$HOME/lab/platform.env"
app=lab-guide
state() { kubectl -n "$LAB_NAMESPACE" get application "$app" -o json | jq '{sync:.status.sync.status,health:.status.health.status,operation:.status.operationState.phase}'; }
refresh() { kubectl -n "$LAB_NAMESPACE" annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite; }
sync() {
 kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"operation":{"sync":{"prune":true}}}'
 kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.operationState.phase}'=Succeeded application/"$app" --timeout=150s
}
kubectl -n "$LAB_NAMESPACE" wait --for=condition=Complete job/lab-preflight --timeout=90s
kubectl -n "$LAB_NAMESPACE" rollout status deployment/lab-web --timeout=90s
kubectl -n "$LAB_NAMESPACE" get job/lab-preflight configmap/lab-settings deployment/lab-web service/lab-web -o json > objects.json
python3 - <<'CHECK'
import json,datetime
objects={o['kind']:o for o in json.load(open('objects.json'))['items']}
def dt(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
assert dt(objects['Job']['status']['completionTime']) <= dt(objects['ConfigMap']['metadata']['creationTimestamp'])
assert dt(objects['Deployment']['metadata']['creationTimestamp']) <= dt(objects['Service']['metadata']['creationTimestamp'])
print('PreSync completed before normal resources; Service was created after Deployment.')
CHECK
state

python3 - <<'CHANGE'
import pathlib,yaml
p=pathlib.Path('repo/manifests/preflight.yaml');x=yaml.safe_load(p.read_text());x['spec']['template']['spec']['containers'][0]['command']=['sh','-c','echo intentional-failure; exit 1'];p.write_text(yaml.safe_dump(x))
p=pathlib.Path('repo/manifests/settings.yaml');x=yaml.safe_load(p.read_text());x['data']['version']='v3';p.write_text(yaml.safe_dump(x))
CHANGE
(cd repo; git add manifests; git commit -m 'Demonstrate a failed PreSync'; git push origin HEAD:main)
refresh
revision=$(cd repo; git rev-parse HEAD)
kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.sync.revision}'="$revision" application/"$app" --timeout=120s
kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"operation":{"sync":{"prune":false}}}'
kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.operationState.phase}'=Failed application/"$app" --timeout=120s
[ "$(kubectl -n "$LAB_NAMESPACE" get cm lab-settings -o jsonpath='{.data.version}')" = v1 ]
echo 'A failed PreSync prevented the new ordinary ConfigMap value from being applied.'
