set -euo pipefail
cd ~/quest
set +e
(
set -e
source platform.env
jq -e '.=={action:"start"}' registry-repair.json >/dev/null
endpoint=$(jq -er .endpoint /run/dq/facts/0/registry-target.json)
curl -fsS --max-time 3 --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$endpoint/v2/" >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'The original registry start and API could not be verified: ✗ [DQ:registry_start]' >&2
  exit "$code"
fi
