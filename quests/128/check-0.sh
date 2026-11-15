set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
timeout --kill-after=1s 8s bash -euo pipefail <<'DQ_LEGACY_CHECKPOINT_0_0'
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
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
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
DQ_LEGACY_CHECKPOINT_0_0
timeout --kill-after=1s 12s python3 -I - <<'DQ_CHECKPOINT_SNAPSHOT'
import csv
import hashlib
import io
import json
import subprocess
import sys
import tarfile
import time
from pathlib import Path

from dq_check import current_pods, named, pod_worker, workload_worker

failed = False
deadline = time.monotonic() + 10


def require(value, marker):
    global failed
    if not value:
        print('Checkpoint condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True


def command(arguments, *, binary=False):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Observation budget exhausted')
    result = subprocess.run(arguments, capture_output=True, text=not binary,
                            timeout=min(6, remaining))
    if result.returncode:
        raise ValueError('Observation unavailable')
    return result.stdout


def get(kind):
    return json.loads(command(['kubectl', 'get', kind, '-o', 'json']))


def resource(items, name):
    matches = [item for item in items if item.get('metadata', {}).get('name') == name]
    if len(matches) != 1:
        raise ValueError('Resource identity')
    return matches[0]


def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or (bool(digest) and isinstance(actual, str)
                                  and actual.partition('@')[2] == digest)


def checkpoint(contract):
    expected = {item['entry'] for item in contract['stores']}
    result = {}
    with tarfile.open(contract['checkpointArchive']) as archive:
        for member in archive:
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            if (name not in expected or name in result or not member.isfile()
                    or member.issparse() or member.size < 1
                    or member.size > contract['maximumEntryBytes']):
                raise ValueError('Unexpected checkpoint member')
            stream = archive.extractfile(member)
            data = stream.read(contract['maximumEntryBytes'] + 1)
            if len(data) != member.size:
                raise ValueError('Truncated checkpoint member')
            result[name] = data
    if set(result) != expected:
        raise ValueError('Incomplete checkpoint')
    reader = csv.DictReader(io.StringIO(result['orders.tsv'].decode()), delimiter='\t')
    orders = list(reader)
    summary = json.loads(result['summary.json'])
    if (len(orders) != len(contract['routes'])
            or reader.fieldnames is None or len(reader.fieldnames) != 4
            or any(set(row) != {'marker', 'generation', 'route', 'units'} for row in orders)
            or {row['route'] for row in orders} != set(contract['routes'])
            or {row['marker'] for row in orders} != {contract['marker']}
            or {int(row['generation']) for row in orders} != {summary['generation']}
            or type(summary['generation']) is not int or summary['generation'] < 1
            or summary['marker'] != contract['marker']
            or any(int(row['units']) < 1 for row in orders)
            or type(summary['total']) is not int
            or sum(int(row['units']) for row in orders) != summary['total']):
        raise ValueError('Inconsistent recovery point')
    return result


facts = json.loads(Path('/run/dq/facts/0/checkpoint-identities.json').read_text())
contract = facts['contract']
try:
    snapshot = checkpoint(contract)
except (KeyError, ValueError, TypeError, AttributeError, IndexError, OSError, tarfile.TarError):
    require(False, 'checkpoint_archive')
    snapshot = None

deployments = {'items': []}
try:
    deployments = get('deployments')
    claims = get('persistentvolumeclaims')
    for name, uid in facts['claims'].items():
        require(resource(claims['items'], name)['metadata']['uid'] == uid, 'checkpoint_identity')
    for name, identity in facts['deployments'].items():
        deployment = resource(deployments['items'], name)
        require(deployment['metadata']['uid'] == identity['uid']
                and same_image(workload_worker(deployment).get('image'), identity['image']),
                'checkpoint_identity')
except (KeyError, ValueError, TypeError, AttributeError, OSError, subprocess.SubprocessError):
    require(False, 'checkpoint_identity')
sys.exit(failed)
DQ_CHECKPOINT_SNAPSHOT
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
 printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_0]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
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
