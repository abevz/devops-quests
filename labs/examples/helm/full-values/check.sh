#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'CHECK'
import yaml,json
def v(name):return json.loads(next(yaml.safe_load_all(open(name+'.yaml')))['data']['payload'])
x=v('merged');assert x['service']=={'port':8080,'type':'NodePort'};assert x['ports']==[9090];assert x['labels']=={'team':'platform','owner':'second'}
assert v('number')['replicaCount']==3 and v('string')['replicaCount']=='3'
assert v('cli-last')['replicaCount']==5
assert v('inferred')['x']==12 and v('inferred')['y'] is True and v('inferred')['z']=='1.10'
assert v('flag-groups')['x']=='012'
assert v('json')['config']=={'port':8080,'enabled':True,'names':['a','b']}
assert v('file')['certificate']==open('certificate.txt').read()
assert v('escaped')['literal']=='a,b' and v('escaped')['annotations']['example.com/key']=='value'
assert v('null')['probe']=={'exec':{'command':['true']}}
assert v('boolean-command')['probe']=={'exec':{'command':[True]}}
assert 'key' in open('malformed.log').read().lower()
print('Deep merge, list replacement, typed flags, file input, escaped commas/dots and null deletion passed.')
CHECK
