set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
checksum=$(cat /run/dq/facts/0/original-ledger.sha256 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$checksum" <<'DQ_ARCHIVE'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import hashlib,sys,tarfile
entries=False;matching=False
try:
    with tarfile.open('ledger.tar') as archive:
        members=archive.getmembers()
        if len(members)==1:
            member=members[0];name=member.name
            while name.startswith('./'):name=name[2:]
            entries=name=='ledger.txt' and member.isfile() and not member.issparse()
            if entries:
                stream=archive.extractfile(member);digest=hashlib.sha256()
                while chunk:=stream.read(65536):digest.update(chunk)
                matching=digest.hexdigest()==sys.argv[1] and len(sys.argv[1])==64
except (OSError,tarfile.TarError,ValueError,KeyError):pass
if not entries:print('ledger.tar contains exactly ledger.txt: ✗ [DQ:entries]')
if not matching:print('ledger.tar ledger.txt checksum = original-ledger.sha256: ✗ [DQ:archive_hash]')
sys.exit(not (entries and matching))
DQ_ARCHIVE
)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
uid=$(cat /run/dq/facts/0/original-pvc-uid 2>/dev/null || true)
live_uid=$(kubectl get pvc ledger -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if ! test -n "$uid" || ! test "$live_uid" = "$uid"; then printf '%s\n' 'ledger PVC UID = original-pvc-uid: ✗ [DQ:pvc_uid]'; failed=1; fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
