set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
jq -e --slurpfile c /run/dq/facts/0/release-catalog.json '(.delete|type)=="array" and (.delete|unique)==[$c[0].obsolete]' retention.json >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
dq_failed=0
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY'
source platform.env
for kind in rollback current obsolete; do
 digest=$(jq -er --arg kind "$kind" '.[$kind]' /run/dq/facts/0/release-catalog.json)
 code=$(curl -sS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' -o /dev/null -w '%{http_code}' "https://$REGISTRY/v2/parcel/manifests/$digest")
 if test "$kind" = obsolete; then test "$code" = 404; else test "$code" = 200; fi
done
DQ_LEGACY
)
[ $? -eq 0 ] || dq_failed=1
(
set -euo pipefail
timeout --kill-after=1s 14s bash -euo pipefail <<'DQ_CURRENT'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
source platform.env
python3 -I - <<'DQ_REGISTRY_BINDINGS'

import base64,hashlib,json,os,ssl,urllib.request
from pathlib import Path
source=json.loads(Path('/run/dq/facts/0/registry-source.json').read_text())
assert os.environ['REGISTRY']==source['endpoint']
assert os.environ['REGISTRY_USER']==source['username']
assert hashlib.sha256(os.environ['REGISTRY_PASSWORD'].encode()).hexdigest()==source['password_sha256']
assert hashlib.sha256(Path('registry-ca.crt').read_bytes()).hexdigest()==source['ca_sha256']
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):
  return None
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect(),
urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile='registry-ca.crt')))
headers={'Authorization':'Basic '+base64.b64encode((source['username']+':'+os.environ['REGISTRY_PASSWORD']).encode()).decode(),
'Accept':'application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'}
def manifest(reference):
 request=urllib.request.Request('https://'+source['endpoint']+'/v2/parcel/manifests/'+reference,headers=headers)
 with opener.open(request,timeout=2) as response:
  body=response.read(2097153)
  assert len(body)<=2097152
  digest='sha256:'+hashlib.sha256(body).hexdigest()
  assert response.headers.get('Docker-Content-Digest')==digest
  return digest

catalog=json.loads(Path('/run/dq/facts/0/release-catalog.json').read_text())
assert manifest('current')==catalog['current']
assert manifest('1')==catalog['rollback']

DQ_REGISTRY_BINDINGS

) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

DQ_CURRENT
)
[ $? -eq 0 ] || dq_failed=1
set -e
test "$dq_failed" -eq 0
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_1]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0

)
[ $? -eq 0 ] || failed=1
exit "$failed"
