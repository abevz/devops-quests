set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
helm get values board -o json | jq -e '(.readinessPort|tonumber)==8080' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
helm history board -o json | jq -e 'length>=3 and .[-1].status=="deployed"' >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl get deployment board -o jsonpath='{.metadata.uid}')" = "$(cat /run/dq/facts/0/original-deployment-uid)"
)
[ $? -eq 0 ] || failed=1
(
set -e
live=$(kubectl get deployment board -o json 2>/dev/null || true)
rendered=$(helm get manifest board 2>/dev/null || true)
python3 -I - /dev/fd/3 /dev/fd/4 3<<<"$live" 4<<<"$rendered" <<'DQ_READINESS'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys,math,re

def worker(document):
    items=[c for c in document["spec"]["template"]["spec"]["containers"] if c.get("name")=="worker"]
    if len(items)!=1:raise ValueError("worker")
    return items[0]

def port(container,value):
    if type(value) is int:return value
    if not isinstance(value,str):raise ValueError("port")
    found=[p["containerPort"] for p in container.get("ports",[]) if p.get("name")==value]
    if len(found)!=1 or type(found[0]) is not int:raise ValueError("named port")
    return found[0]

def readiness(document,tcp=False):
    container=worker(document);probe=container.get("readinessProbe",{})
    kinds=[name for name in ("httpGet","tcpSocket","exec","grpc") if probe.get(name) is not None]
    if len(kinds)!=1 or kinds[0] not in (["httpGet","tcpSocket"] if tcp else ["httpGet"]):return False
    action=probe[kinds[0]]
    if action.get("host","")!="":return False
    if kinds[0]=="httpGet" and action.get("scheme","HTTP")!="HTTP":return False
    return port(container,action.get("port"))==8080
import yaml
try:
    live=json.loads(sys.argv[1])
    rendered=[doc for doc in yaml.safe_load_all(sys.argv[2]) if isinstance(doc,dict) and doc.get("kind")=="Deployment" and doc.get("metadata",{}).get("name")=="board"]
    ok=len(rendered)==1 and readiness(live,tcp=True) and readiness(rendered[0],tcp=True)
except (ValueError,KeyError,TypeError,AttributeError,yaml.YAMLError):
    ok=False
sys.exit(not ok)
DQ_READINESS
)
[ $? -eq 0 ] || failed=1
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
)
[ $? -eq 0 ] || failed=1
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- -T 3 http://127.0.0.1:8080)" = north-67
)
[ $? -eq 0 ] || failed=1
exit "$failed"
