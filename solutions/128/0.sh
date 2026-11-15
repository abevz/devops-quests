set -euo pipefail
cd ~/quest
kubectl exec deployment/ledger -- tar cf - -C /data ledger.txt > ledger.tar
python3 -I - <<'DQ_CHECKPOINT_REFERENCE'
import io,json,subprocess,tarfile,time
from pathlib import Path
contract=json.loads(Path('checkpoint-contract.json').read_text())
deadline=time.monotonic()+15
while True:
    locked=subprocess.run(['kubectl','exec','deployment/ledger','--','mkdir','/data/.checkpoint-lock'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    if locked.returncode==0:
        break
    if time.monotonic()>=deadline:
        raise RuntimeError('Checkpoint lock unavailable')
    time.sleep(0.1)
try:
    path=Path(contract['checkpointArchive'])
    temporary=path.with_suffix('.tar.new')
    with tarfile.open(temporary,'w') as archive:
        for store in contract['stores']:
            data=subprocess.check_output(['kubectl','exec','deployment/'+store['deployment'],'--','cat',store['path']])
            item=tarfile.TarInfo(store['entry']);item.size=len(data)
            archive.addfile(item,io.BytesIO(data))
    temporary.replace(path)
finally:
    subprocess.run(['kubectl','exec','deployment/ledger','--','rmdir','/data/.checkpoint-lock'],check=True)
DQ_CHECKPOINT_REFERENCE
