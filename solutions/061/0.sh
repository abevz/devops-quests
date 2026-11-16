set -euo pipefail
cd ~/quest
source platform.env
umask 077
repair=$(mktemp)
trap 'rm -f "$repair"' EXIT
python3 -I - "$repair" <<'DQ_CREDENTIALS'
import base64,json,os,subprocess,sys
from pathlib import Path
subprocess.run(['git','config','--global','--unset-all','http.extraHeader'],check=True)
header=base64.b64encode((os.environ['GIT_USER']+':'+os.environ['GIT_PASSWORD']).encode()).decode()
p=Path.home()/'.gitconfig'
with p.open('a') as output:output.write('\n[http]\n\textraHeader = Authorization: Basic '+header+'\n')
p.chmod(0o600)
Path(sys.argv[1]).write_text(json.dumps({'stringData':{'url':os.environ['GIT_URL'],'username':os.environ['GIT_USER'],'password':os.environ['GIT_PASSWORD'],'type':'git'}}))
DQ_CREDENTIALS
git -C repository ls-remote "$GIT_URL" refs/heads/main >/dev/null
kubectl -n "$ARGO_NAMESPACE" patch secret station-repository --type merge --patch-file "$repair"
rm -f "$repair"
trap - EXIT
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null && kubectl rollout status deployment/board --timeout=2s >/dev/null 2>&1; then break; fi
 sleep 1
done
