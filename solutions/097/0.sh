set -euo pipefail
cd ~/quest
source platform.env
test "$(sha256sum recovery-image.tar | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/archive.sha256)"
docker load -i recovery-image.tar
docker push "$REGISTRY/parcel:1"
image=$(cat /run/dq/facts/0/release-image)
python3 - "$image" <<'SOURCE'
import sys,yaml
from pathlib import Path
p=Path('repository/manifests/web.yaml');documents=list(yaml.safe_load_all(p.read_text()))
for obj in documents:
 if obj['kind']=='Deployment':
  next(c for c in obj['spec']['template']['spec']['containers'] if c['name']=='worker')['image']=sys.argv[1]
p.write_text(yaml.safe_dump_all(documents,sort_keys=False))
SOURCE
git -C repository add manifests/web.yaml
git -C repository commit -m 'Activate the recovered immutable release'
git -C repository push origin main
kubectl annotate application release argocd.argoproj.io/refresh=hard --overwrite
kubectl set image cronjob/archive-scan "worker=$image"
kubectl create job --from=cronjob/archive-scan restored-execution
kubectl wait --for=condition=Complete job/restored-execution --timeout=120s
kubectl rollout status deployment/archive-web --timeout=90s
for i in $(seq 1 60); do
 if kubectl get application release -o json | jq -e --arg rev "$(git -C repository rev-parse HEAD)" '.status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null; then break; fi
 sleep 1
done
