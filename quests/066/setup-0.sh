set -euo pipefail
cd ~/quest
source platform.env
mkdir -p variant-context
for kind in obsolete current; do
 printf 'FROM %s
LABEL signalrail.retention="%s-66"
' "$PRIVATE_IMAGE" "$kind" > variant-context/Dockerfile
 docker build --network=none -t "$REGISTRY/parcel:$kind" variant-context >/dev/null
 docker push "$REGISTRY/parcel:$kind" >/dev/null
done
python3 - <<'CATALOG'
import json,os,subprocess
catalog={'rollback':os.environ['PRIVATE_IMAGE'].split('@')[1]}
for k in ('obsolete','current'):
 refs=json.loads(subprocess.check_output(['docker','image','inspect',os.environ['REGISTRY']+'/parcel:'+k,'--format','{{json .RepoDigests}}'],text=True))
 catalog[k]=next(r.split('@')[1] for r in refs if r.startswith(os.environ['REGISTRY']+'/parcel@'))
assert len(set(catalog.values()))==3
open('release-catalog.json','w').write(json.dumps(catalog))
open('retention.json','w').write(json.dumps({'delete':[catalog['rollback']]}))
CATALOG
cat > prune.sh <<'DQ_ASSET'
#!/bin/bash
set -euo pipefail
cd ~/quest
source platform.env
python3 - <<'VALIDATE'
import json,re
c=json.load(open('/run/dq/facts/0/release-catalog.json'));p=json.load(open('retention.json'))
assert len(p['delete'])==1
for d in p['delete']:
 assert re.fullmatch(r'sha256:[0-9a-f]{64}',d)
 assert d==c['obsolete'], 'Refusing to remove an unapproved release'
VALIDATE
while read -r digest; do
 curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" --request DELETE "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null
done < <(jq -r '.delete[]' retention.json)
DQ_ASSET
