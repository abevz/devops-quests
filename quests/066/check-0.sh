set -euo pipefail
cd ~/quest
source platform.env
jq -e --slurpfile c /run/dq/facts/0/release-catalog.json '.delete==[$c[0].obsolete]' retention.json >/dev/null
for kind in rollback current obsolete; do
 digest=$(jq -er --arg kind "$kind" '.[$kind]' /run/dq/facts/0/release-catalog.json)
 code=$(curl -sS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' -o /dev/null -w '%{http_code}' "https://$REGISTRY/v2/parcel/manifests/$digest")
 if test "$kind" = obsolete; then test "$code" = 404; else test "$code" = 200; fi
done
