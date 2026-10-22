set -euo pipefail
cd ~/quest
source platform.env
test "$(sha256sum recovery-image.tar | cut -d' ' -f1)" = "$(cat /run/dq/facts/0/archive.sha256)"
image=$(cat /run/dq/facts/0/release-image);digest=${image##*@}
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" > /tmp/restored-manifest.json
test "sha256:$(sha256sum /tmp/restored-manifest.json | cut -d' ' -f1)" = "$digest"
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/1" > /tmp/restored-tag.json
cmp /tmp/restored-manifest.json /tmp/restored-tag.json
config=$(jq -er .config.digest /tmp/restored-manifest.json)
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY/v2/parcel/blobs/$config" >/dev/null
