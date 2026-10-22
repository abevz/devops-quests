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
if [ ! -d repo/.git ]; then git clone "$GIT_URL" repo; else git -C repo pull --ff-only origin main; fi
mkdir -p repo/manifests
python3 - <<'FILES'
import os,pathlib,yaml
p=pathlib.Path('repo/manifests')
objects=[
 {'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'lab-settings','annotations':{'argocd.argoproj.io/sync-wave':'-1'}},'data':{'version':'v1'}},
 {'apiVersion':'batch/v1','kind':'Job','metadata':{'name':'lab-preflight','annotations':{'argocd.argoproj.io/hook':'PreSync','argocd.argoproj.io/hook-delete-policy':'BeforeHookCreation'}},'spec':{'backoffLimit':0,'activeDeadlineSeconds':40,'template':{'spec':{'restartPolicy':'Never','containers':[{'name':'check','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never','command':['sh','-c','echo preflight; sleep 3; exit 0']}]}}}},
 {'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'lab-web','annotations':{'argocd.argoproj.io/sync-wave':'0'}},'spec':{'replicas':1,'selector':{'matchLabels':{'app':'lab-web'}},'template':{'metadata':{'labels':{'app':'lab-web'}},'spec':{'containers':[{'name':'app','image':os.environ['DQ_APP_IMAGE'],'imagePullPolicy':'Never','command':['sleep','3600'],'resources':{'requests':{'cpu':'10m','memory':'8Mi'},'limits':{'cpu':'100m','memory':'32Mi'}}}]}}}},
 {'apiVersion':'v1','kind':'Service','metadata':{'name':'lab-web','annotations':{'argocd.argoproj.io/sync-wave':'1'}},'spec':{'selector':{'app':'lab-web'},'ports':[{'port':80,'targetPort':8080}]}}
]
for obj,name in zip(objects,['settings','preflight','web','service']): (p/(name+'.yaml')).write_text(yaml.safe_dump(obj))
FILES
(cd repo; git add manifests; git commit -m 'Prepare Lab experiment' || test -z "$(git status --porcelain)"; git push origin HEAD:main)
python3 - <<'APPLICATION' | kubectl -n "$LAB_NAMESPACE" apply -f -
import os,yaml
print(yaml.safe_dump({'apiVersion':'argoproj.io/v1alpha1','kind':'Application','metadata':{'name':'lab-guide'},'spec':{'project':'station','source':{'repoURL':os.environ['GIT_URL'],'targetRevision':'main','path':'manifests'},'destination':{'server':'https://kubernetes.default.svc','namespace':os.environ['LAB_NAMESPACE']},'syncPolicy':{'retry':{'limit':0}}}}))
APPLICATION
refresh
sync
state
