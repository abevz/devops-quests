set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
checksum=$(cat /run/dq/facts/0/original-ledger.sha256 2>/dev/null || true)
if ! python3 -c 'import sys,tarfile; t=tarfile.open("ledger.tar"); sys.exit(t.getnames()!=["ledger.txt"])' >/dev/null 2>&1; then printf '%s\n' 'ledger.tar contains exactly ledger.txt: ✗ [DQ:entries]'; failed=1; fi
if ! archive=$(tar xOf ledger.tar ledger.txt 2>/dev/null | sha256sum | awk '{print $1}'); then archive=; fi
if ! test -n "$checksum" || ! test "$archive" = "$checksum"; then printf '%s\n' 'ledger.tar ledger.txt checksum = original-ledger.sha256: ✗ [DQ:archive_hash]'; failed=1; fi
exit "$failed"

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
