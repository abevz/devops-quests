set -euo pipefail
cd ~/quest
source platform.env
image=$(jq -er .image /run/dq/facts/0/release-evidence.json)
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
