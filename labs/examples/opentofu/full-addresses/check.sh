#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import json
def ids(name):return [i['attributes']['id'] for r in json.load(open(name))['resources'] for i in r['instances']]
assert ids('before.json')==ids('moved.json')==ids('renamed.json')
assert any('delete' in r['change']['actions'] for r in json.load(open('broken.json'))['resource_changes'])
assert not open('forgotten.out').read().strip()
assert 'instance' in open('unsupported.log').read().lower()
print('Root-to-module move and module rename preserve identity; broken rename replaces; removed forgets ownership.')
CHECK
