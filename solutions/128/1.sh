set -euo pipefail
cd ~/quest
kubectl exec -i deployment/ledger -- tar xf - -C /data < ledger.tar
python3 -I - <<'DQ_CHECKPOINT_RESTORE'
import json,shlex,subprocess,tarfile
from pathlib import Path
contract=json.loads(Path('checkpoint-contract.json').read_text())
with tarfile.open(contract['checkpointArchive']) as archive:
    for store in contract['stores']:
        data=archive.extractfile(store['entry']).read()
        subprocess.run(['kubectl','exec','-i','deployment/'+store['deployment'],'--','sh','-c',
                        'cat > '+shlex.quote(store['path'])],input=data,check=True)
DQ_CHECKPOINT_RESTORE
