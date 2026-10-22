set -euo pipefail
cd ~/quest
source platform.env
printf '%s
' "$PRIVATE_IMAGE" > release-image
docker save "$REGISTRY/parcel:1" -o recovery-image.tar
sha256sum recovery-image.tar | cut -d' ' -f1 > archive.sha256
digest=${PRIVATE_IMAGE##*@}
curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -X DELETE "https://$REGISTRY/v2/parcel/manifests/$digest"
test "$(curl -sS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -o /dev/null -w '%{http_code}' "https://$REGISTRY/v2/parcel/manifests/$digest")" = 404
