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
document=$(kubectl get daemonset relay -o json 2>/dev/null || true)
python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_ELIGIBLE'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    document=json.loads(sys.argv[1]);generation=document["metadata"]["generation"];status=document["status"]
    ok=type(generation) is int and generation>0 and status.get("observedGeneration")==generation and status.get("desiredNumberScheduled")==1 and status.get("updatedNumberScheduled")==1 and status.get("numberMisscheduled",0)==0
except (KeyError,ValueError,TypeError,AttributeError):ok=False
if not ok:print("daemonset/relay current controller is eligible on the bay node: ✗ [DQ:node_selector]")
sys.exit(not ok)
DQ_ELIGIBLE
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
set -euo pipefail
cd ~/quest
failed=0
document=$(timeout 2s kubectl get daemonset relay -o json 2>/dev/null || true)
if ! python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_SECURITY'
import sys

def _dq_read_argument(value):
    if not value.startswith('/dev/fd/'):
        return value
    with open(value, encoding='utf-8', newline='') as source:
        return source.read().removesuffix('\n')

sys.argv = [_dq_read_argument(value) for value in sys.argv]

import json,sys
try:
    document=json.loads(sys.argv[1]);pod=document["spec"]["template"]["spec"]
    regular=pod["containers"];initial=pod.get("initContainers",[]) or []
    if not isinstance(regular,list) or not regular or not isinstance(initial,list):raise ValueError("containers")
    containers=regular+initial;policy=pod.get("securityContext",{}) or {}
    contexts=[c.get("securityContext",{}) or {} for c in containers]
    if not isinstance(policy,dict) or not all(isinstance(c,dict) for c in contexts):raise ValueError("context")
    valid=True
except (ValueError,KeyError,TypeError,AttributeError):
    pod={};regular=[];containers=[];policy={};contexts=[];valid=False

def emit(marker,label,condition):
    global failed
    if not valid or not condition:
        failed=True;print(label+": ✗ [DQ:"+marker+"]")

def profile(context):
    value=context.get("seccompProfile")
    if value is None:return None
    return value.get("type","invalid") if isinstance(value,dict) else "invalid"

def positive_ids():
    return all(type(v) is int and v>0 for c in [policy]+contexts for v in [c.get("runAsUser")] if v is not None)

def nonroot():
    no_false=all(c.get("runAsNonRoot") in (None,True) and c.get("runAsNonRoot") is not False for c in [policy]+contexts)
    inherited=all((c.get("runAsNonRoot") if c.get("runAsNonRoot") is not None else policy.get("runAsNonRoot")) is True for c in contexts)
    return no_false and inherited and positive_ids()

def default_filter():
    return all(profile(c) in (None,"RuntimeDefault") for c in [policy]+contexts) and all((profile(c) or profile(policy))=="RuntimeDefault" for c in contexts)

def caps(context,key):
    value=context.get("capabilities",{}) or {}
    if not isinstance(value,dict):return None
    result=value.get(key,[]) or []
    return result if isinstance(result,list) else None

failed=False
for field in ("hostNetwork","hostPID","hostIPC"):
    emit("host_"+field.lower(),"daemonset/relay "+field+" != true",pod.get(field) is not True)
volumes=pod.get("volumes",[]) or []
emit("hostpath","daemonset/relay volumes hostPath = none",isinstance(volumes,list) and all(isinstance(v,dict) and v.get("hostPath") is None for v in volumes))
emit("nonroot","daemonset/relay effective containers are non-root",nonroot())
if False:emit("uid","daemonset/relay explicit UIDs are positive",positive_ids())
emit("seccomp","daemonset/relay effective default syscall filter",default_filter())
emit("security_privileged","daemonset/relay containers privileged != true",all(c.get("privileged") is not True for c in contexts))
emit("security_allowprivilegeescalation","daemonset/relay containers cannot gain privileges",all(c.get("allowPrivilegeEscalation") is False for c in contexts))
if False:emit("security_readonlyrootfilesystem","daemonset/relay containers have root filesystems that are not writable",all(c.get("readOnlyRootFilesystem") is True for c in contexts))
emit("security_drop","daemonset/relay containers drop ALL capabilities",all(caps(c,"drop") is not None and "ALL" in caps(c,"drop") for c in contexts))
emit("security_add","daemonset/relay containers add no capabilities",all(caps(c,"add")==[] for c in contexts))
if False:
    emit("security_seccomp","daemonset/relay containers do not override with another filter",all(profile(c) in (None,"RuntimeDefault") for c in contexts))
    try:
        if not isinstance(volumes,list):raise ValueError("volumes")
        by_name={v["name"]:v for v in volumes}
        if len(by_name)!=len(volumes):raise ValueError("volume identity")
        workers=[c for c in regular if c.get("name")=="worker"]
        if len(workers)!=1:raise ValueError("worker")
        tmp=[m for m in workers[0].get("volumeMounts",[]) if m.get("mountPath")=="/tmp"]
        if len(tmp)!=1:raise ValueError("tmp mount")
        temporary=by_name[tmp[0]["name"]]
        volume_ok=isinstance(temporary.get("emptyDir"),dict)
        mount_ok=volume_ok and tmp[0].get("readOnly") is not True
        def readonly(mount):
            source=by_name[mount["name"]]
            if mount.get("readOnly") is True:return True
            if any(source.get(key) is not None for key in ("configMap","secret","projected","downwardAPI")):return True
            return any(isinstance(source.get(key),dict) and source[key].get("readOnly") is True for key in ("persistentVolumeClaim","csi"))
        mounts_ok=all((m.get("name")==tmp[0]["name"] and m.get("mountPath")=="/tmp") or readonly(m) for c in containers for m in c.get("volumeMounts",[]))
    except (KeyError,ValueError,TypeError,AttributeError):volume_ok=mount_ok=mounts_ok=False
    emit("volume","daemonset/relay temporary volume is emptyDir",volume_ok)
    emit("mount","daemonset/relay worker temporary storage at /tmp is writable",mount_ok)
    emit("mounts","daemonset/relay other mounts are not writable",mounts_ok)
sys.exit(failed)
DQ_SECURITY
then failed=1; fi
exit "$failed"
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
set -euo pipefail
cd ~/quest
failed=0
daemonset=$(kubectl get daemonset relay -o json 2>/dev/null || true)
uid=$(jq -r '.metadata.uid // ""' <<<"$daemonset" 2>/dev/null || true)
field=desiredNumberScheduled
  if ! jq -e --arg field "$field" '.status[$field]==1' <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay $field = 1: ✗ [DQ:status_${field,,}]"
    failed=1
  fi
field=numberReady
  if ! jq -e --arg field "$field" '.status[$field]==1' <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay $field = 1: ✗ [DQ:status_${field,,}]"
    failed=1
  fi
field=numberAvailable
  if ! jq -e --arg field "$field" '.status[$field]==1' <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay $field = 1: ✗ [DQ:status_${field,,}]"
    failed=1
  fi
if ! test -n "$uid" || ! kubectl get pods -l app=relay -o json 2>/dev/null | jq -e --arg node "$DQ_NODE_NAME" --arg uid "$uid" 'any(.items[];.metadata.deletionTimestamp==null and .spec.nodeName==$node and any(.metadata.ownerReferences[]?;.kind=="DaemonSet" and .uid==$uid and .controller==true) and any(.status.containerStatuses[]?;.ready==true))' >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay owned Ready Pod on DQ_NODE_NAME: ✗ [DQ:owned]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
(
set -e
set -euo pipefail
cd ~/quest
failed=0
if ! test "$(kubectl exec --pod-running-timeout=2s daemonset/relay -- wget -qO- -T 3 http://127.0.0.1:8080 2>/dev/null)" = north-103; then
  printf '%s\n' 'daemonset/relay Pod 127.0.0.1:8080 = north-103: ✗ [DQ:local_http]'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s daemonset/relay -- wget -qO- -T 3 http://relay:8080 2>/dev/null)" = north-103; then
  printf '%s\n' 'relay:8080 = north-103: ✗ [DQ:service_http]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
