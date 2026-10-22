#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import yaml,json
def cm(path):
 return next(x['data'] for x in yaml.safe_load_all(open(path)) if x['kind']=='ConfigMap')
assert cm('merged.yaml')['message']=='override'
assert json.loads(cm('merged.yaml')['features'])==['c']
assert cm('string.yaml')['message']=='true' and cm('string.yaml')['messageType']=='string'
assert json.loads(cm('json.yaml')['features'])==['x','y']
assert cm('file.yaml')['message']=='from-file\n'
print('Later files override values; lists replace; explicit string/JSON/file inputs preserve their intended forms.')
CHECK
