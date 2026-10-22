set -euo pipefail
cd ~/quest
jq '.spec.source.path="manifests"' repository/apps/child.json > /tmp/child.json
cp /tmp/child.json repository/apps/child.json
git -C repository add apps/child.json
git -C repository commit -m 'Restore child source path'
git -C repository push origin main
kubectl annotate application parent argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if bash wait-apps.sh; then break; fi
 sleep 1
done
bash wait-apps.sh
