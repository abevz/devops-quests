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

source platform.env
python3 -I - <<'DQ_REGISTRY_SOURCE'
import hashlib,json,os
from pathlib import Path
contract={'endpoint':os.environ['REGISTRY'],'username':os.environ['REGISTRY_USER'],
'password_sha256':hashlib.sha256(os.environ['REGISTRY_PASSWORD'].encode()).hexdigest(),
'ca_sha256':hashlib.sha256(Path('registry-ca.crt').read_bytes()).hexdigest()}
Path('registry-source.json').write_text(json.dumps(contract))
DQ_REGISTRY_SOURCE

# The workspace is intentionally a scaffold, not a complete deletion adapter.
printf '%s\n' '#!/bin/bash' 'set -euo pipefail' > prune.sh
docker tag "$PRIVATE_IMAGE" "$REGISTRY/parcel:current"
docker push "$REGISTRY/parcel:current" >/dev/null
