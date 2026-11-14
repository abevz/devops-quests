set -euo pipefail
cd ~/quest
source platform.env
image=$(kubectl get deployment board -o jsonpath='{.spec.template.spec.containers[?(@.name=="worker")].image}')
digest=${image##*@}
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" > manifest.json
test "sha256:$(sha256sum manifest.json | cut -d' ' -f1)" = "$digest"
config=$(jq -er .config.digest manifest.json)
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY/v2/parcel/blobs/$config" > config.json
commit=$(jq -er '.config.Labels["org.opencontainers.image.revision"]' config.json)
git -C repository fetch origin main
git -C repository merge-base --is-ancestor "$commit" origin/main
test "$(git -C repository show "$commit:site/index.html")" = north-91
jq -n --arg image "$image" --arg commit "$commit" --arg repo "$GIT_URL" '{image:$image,commit:$commit,repo:$repo}' > provenance.json
python3 - <<'PUBLISH_RECORD'
import yaml,json
from pathlib import Path
p=Path('repository/manifests/provenance.yaml');v=yaml.safe_load(p.read_text())
v['data']['provenance.json']=json.dumps(json.loads(Path('provenance.json').read_text()),sort_keys=True)
p.write_text(yaml.safe_dump(v,sort_keys=False))
PUBLISH_RECORD
git -C repository add manifests/provenance.yaml
git -C repository commit -m 'Publish verified image-source record'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
kubectl annotate application board argocd.argoproj.io/refresh=hard --overwrite
for i in $(seq 1 90); do
 if kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" '.status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null; then break; fi
 sleep 1
done
# A subPath consumer retains its mounted file until that Pod is replaced.
kubectl rollout restart deployment/board
kubectl rollout status deployment/board --timeout=90s
for i in $(seq 1 30); do
 if kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://board:8080/provenance.json | jq -e --slurpfile expected provenance.json '.==$expected[0]' >/dev/null; then break; fi
 sleep 1
done
