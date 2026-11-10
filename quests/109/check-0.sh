set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set -euo pipefail
cd ~/quest
failed=0
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
if ! timeout 2s kubectl get namespace "$DQ_NAMESPACE" -o json 2>/dev/null | jq -e '.metadata.labels["pod-security.kubernetes.io/enforce"]=="restricted"' >/dev/null 2>&1; then
  printf '%s\n' 'namespace pod-security.kubernetes.io/enforce = restricted: ✗ [DQ:namespace]'
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
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
if ! jq -e '.spec.replicas==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board replicas = 1: ✗ [DQ:replicas]'
  failed=1
fi
if ! jq -e '.status.readyReplicas==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board readyReplicas = 1: ✗ [DQ:ready]'
  failed=1
fi
if ! jq -e '.spec.template.spec.containers | length==1 and .[0].name=="worker"' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board containers = [worker]: ✗ [DQ:containers]'
  failed=1
fi
exit "$failed"

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
document=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
if ! python3 -I - /dev/fd/3 3<<<"$document" <<'DQ_SECURITY'
import sys

from dq_check import read_argument as _dq_read_argument

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

from dq_check import seccomp_profile as profile

from dq_check import positive_user_ids as _dq_positive_ids

def positive_ids():
    return _dq_positive_ids(policy, contexts)

from dq_check import nonroot_policy as _dq_nonroot

def nonroot():
    return _dq_nonroot(policy, contexts)

from dq_check import runtime_default_policy as _dq_default_filter

def default_filter():
    return _dq_default_filter(policy, contexts)

from dq_check import capability_list as caps

failed=False
for field in ("hostNetwork","hostPID","hostIPC"):
    emit("host_"+field.lower(),"deployment/board "+field+" != true",pod.get(field) is not True)
volumes=pod.get("volumes",[]) or []
emit("hostpath","deployment/board volumes hostPath = none",isinstance(volumes,list) and all(isinstance(v,dict) and v.get("hostPath") is None for v in volumes))
emit("nonroot","deployment/board effective containers are non-root",nonroot())
if True:emit("uid","deployment/board explicit UIDs are positive",positive_ids())
emit("seccomp","deployment/board effective default syscall filter",default_filter())
emit("security_privileged","deployment/board containers privileged != true",all(c.get("privileged") is not True for c in contexts))
emit("security_allowprivilegeescalation","deployment/board containers cannot gain privileges",all(c.get("allowPrivilegeEscalation") is False for c in contexts))
if True:emit("security_readonlyrootfilesystem","deployment/board containers have root filesystems that are not writable",all(c.get("readOnlyRootFilesystem") is True for c in contexts))
emit("security_drop","deployment/board containers drop ALL capabilities",all(caps(c,"drop") is not None and "ALL" in caps(c,"drop") for c in contexts))
emit("security_add","deployment/board containers add no capabilities",all(caps(c,"add")==[] for c in contexts))
if True:
    emit("security_seccomp","deployment/board containers do not override with another filter",all(profile(c) in (None,"RuntimeDefault") for c in contexts))
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
        from dq_check import readonly_mount as _dq_readonly

        def readonly(mount):
            return _dq_readonly(mount, by_name)
        mounts_ok=all((m.get("name")==tmp[0]["name"] and m.get("mountPath")=="/tmp") or readonly(m) for c in containers for m in c.get("volumeMounts",[]))
    except (KeyError,ValueError,TypeError,AttributeError):volume_ok=mount_ok=mounts_ok=False
    emit("volume","deployment/board temporary volume is emptyDir",volume_ok)
    emit("mount","deployment/board worker temporary storage at /tmp is writable",mount_ok)
    emit("mounts","deployment/board other mounts are not writable",mounts_ok)
sys.exit(failed)
DQ_SECURITY
then failed=1; fi
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- sh -c 'awk '\''$2=="/" {found=1; if ($4 ~ /(^|,)ro(,|$)/) ok=1} END {exit !(found && ok)}'\'' /proc/mounts' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board / mount = ro: ✗ [DQ:root]'
  failed=1
fi
live_uid=$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- id -u 2>/dev/null || true)
if ! [[ "$live_uid" =~ ^[0-9]+$ ]] || ! test "$live_uid" -gt 0; then
  printf '%s\n' 'deployment/board id -u is positive: ✗ [DQ:live_uid]'
  failed=1
fi
if ! timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -c worker -- sh -c 'printf writable > /tmp/write-probe; test "$(cat /tmp/write-probe)" = writable' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board /tmp write/read: ✗ [DQ:tmp]'
  failed=1
fi
exit "$failed"
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
set -euo pipefail
cd ~/quest
failed=0
board=$(timeout 2s kubectl get deployment board -o json 2>/dev/null || true)
if ! test "$(timeout 4s kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-109; then
  printf '%s\n' 'board:8080 = north-109: ✗ [DQ:http]'
  failed=1
fi
exit "$failed"

)
[ $? -eq 0 ] || failed=1
exit "$failed"
