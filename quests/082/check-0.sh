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
if ! (
helm status board -o json | jq -e '.info.status=="deployed"' >/dev/null
); then
  printf '%s\n' 'The original release condition is unmet: ✗ [DQ:release_status]'
  exit 1
fi
for release in dispatcher archive; do
 if ! helm status "$release" -o json | jq -e '.info.status=="deployed"' >/dev/null; then
  printf '%s\n' 'Every retained release must be deployed: ✗ [DQ:release_status]'
  exit 1
 fi
done
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
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
if ! (
helm get values board --all -o json | jq -e '(.port|tostring)=="8080"' >/dev/null
); then
  printf '%s\n' 'The original release condition is unmet: ✗ [DQ:release_values]'
  exit 1
fi
python3 -I - <<'DQ_RELEASE'
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

from dq_check import workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Release propagation condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise ValueError('Current release observation failed')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current release inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    return json.loads(command(args, marker))

def get(kind, name, marker='release_identity'):
    return document(['kubectl', 'get', kind, name, '-o', 'json'], marker)

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

facts = json.loads(Path('/run/dq/facts/0/release-identities.json').read_text())
contract = facts['contract']
producer = contract['producer']
consumers = contract['consumers']
service = get('service', producer['service'], 'release_values')
namespace = os.environ['DQ_NAMESPACE']
base = producer['service']
hosts = {base, base + '.' + namespace, base + '.' + namespace + '.svc', base + '.' + namespace + '.svc.cluster.local', service.get('spec', {}).get('clusterIP')}

def current_upstream(value):
    try:
        uri = urlsplit(value)
        return uri.scheme == 'http' and uri.hostname in hosts and uri.port == contract['servicePort'] and uri.path == contract['metadataPath'] and not uri.query and not uri.fragment and uri.username is None and uri.password is None
    except (ValueError, TypeError, AttributeError):
        return False

all_releases = [producer] + consumers
for endpoint in all_releases:
    values = document(['helm', 'get', 'values', endpoint['release'], '--all', '-o', 'json'], 'release_values')
    require(isinstance(values, dict) and same_image(values.get('image'), facts['image']), 'release_images')
    if endpoint == producer:
        require(values.get('publicationId') == facts['publication']['publication_id'], 'release_values')
    else:
        require(str(values.get('upstreamPort')) == str(contract['servicePort']) and values.get('expectedPublication') == facts['publication']['publication_id'], 'release_values')
    if endpoint != producer:
        expected_environment = {'UPSTREAM': 'http://' + producer['service'] + ':' + str(contract['servicePort']) + contract['metadataPath'], 'EXPECTED_PUBLICATION': facts['publication']['publication_id']}
        # Observe effective application inputs rather than requiring literal
        # env entries: ConfigMap/Secret references and envFrom remain valid.
        for name, expected in expected_environment.items():
            actual = command(['kubectl', 'exec', 'deployment/' + endpoint['deployment'], '-c', 'worker', '--', 'printenv', name], 'release_values').strip()
            require(current_upstream(actual) if name == 'UPSTREAM' else actual == expected, 'release_values')
sys.exit(int(failed))
DQ_RELEASE
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
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
if ! (
kubectl rollout status deployment/relay --timeout=3s >/dev/null
); then
  printf '%s\n' 'The original release condition is unmet: ✗ [DQ:release_rollout]'
  exit 1
fi
for deployment in dispatcher archive; do
 if ! kubectl rollout status "deployment/$deployment" --timeout=3s >/dev/null; then
  printf '%s\n' 'Every consumer must complete its rollout: ✗ [DQ:release_rollout]'
  exit 1
 fi
done
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
  printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_2]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
(
set -e
dq_probe_output=$(mktemp)
trap 'rm -f "$dq_probe_output"' EXIT
set +e
(
set -euo pipefail
if ! (
test "$(kubectl exec deployment/relay -- wget -qO- -T 3 http://127.0.0.1:8080)" = signalrail
); then
  printf '%s\n' 'The original release condition is unmet: ✗ [DQ:release_publication]'
  exit 1
fi
python3 -I - <<'DQ_RELEASE'
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

from dq_check import workload_worker

failed = False

def require(value, marker):
    global failed
    if not value:
        print('Release propagation condition is unmet: ✗ [DQ:' + marker + ']')
        failed = True

def command(args, marker):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise ValueError('Current release observation failed')
        return result.stdout
    except (ValueError, OSError, subprocess.SubprocessError):
        print('Current release inputs are unavailable: ✗ [DQ:' + marker + ']')
        sys.exit(1)

def document(args, marker):
    return json.loads(command(args, marker))

def get(kind, name, marker='release_identity'):
    return document(['kubectl', 'get', kind, name, '-o', 'json'], marker)

def same_image(actual, expected):
    digest = expected.partition('@')[2]
    return actual == expected or bool(digest) and isinstance(actual, str) and actual.partition('@')[2] == digest

facts = json.loads(Path('/run/dq/facts/0/release-identities.json').read_text())
contract = facts['contract']
producer = contract['producer']
consumers = contract['consumers']
for key, original in facts['identities'].items():
    kind, name = key.split('/', 1)
    current = get(kind, name)
    require(current.get('metadata', {}).get('uid') == original, 'release_identity')
    if kind == 'deployment':
        require(same_image(workload_worker(current).get('image'), facts['image']), 'release_images')
source = get('configmap', producer['configMap'], 'release_source')
require(all(source.get('data', {}).get(k) == v for k, v in facts['data'].items()), 'release_source')
for endpoint in [producer] + consumers:
    uri = 'http://' + endpoint['service'] + ':' + str(contract['servicePort']) + contract['metadataPath']
    actual = document(['kubectl', 'exec', 'deployment/' + producer['deployment'], '-c', 'worker', '--', 'wget', '-qO-', '-T', '3', uri], 'release_publication')
    require(actual == facts['publication'], 'release_publication')
sys.exit(int(failed))
DQ_RELEASE
) >"$dq_probe_output" 2>/dev/null
dq_probe_status=$?
set -e
cat "$dq_probe_output"
if [ "$dq_probe_status" -ne 0 ] && ! grep -Eq '\[DQ:[a-z0-9_]+\]' "$dq_probe_output"; then
  printf '%s\n' 'Current inputs could not verify this objective: ✗ [DQ:probe_0_3]'
fi
rm -f "$dq_probe_output"
trap - EXIT
test "$dq_probe_status" -eq 0
)
[ $? -eq 0 ] || failed=1
exit "$failed"
