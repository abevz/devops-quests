set -euo pipefail
cd ~/quest
failed=0
board=$(kubectl get deployment board -o json 2>/dev/null || true)
if ! kubectl get namespace "$DQ_NAMESPACE" -o json 2>/dev/null | jq -e '.metadata.labels["pod-security.kubernetes.io/enforce"]=="restricted"' >/dev/null 2>&1; then
  printf '%s\n' 'namespace pod-security.kubernetes.io/enforce = restricted: ✗'
  failed=1
fi
if ! jq -e '.spec.replicas==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board replicas = 1: ✗'
  failed=1
fi
if ! jq -e '.status.readyReplicas==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board readyReplicas = 1: ✗'
  failed=1
fi
if ! jq -e '.spec.template.spec.containers | length==1 and .[0].name=="worker"' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board containers = [worker]: ✗'
  failed=1
fi
for field in hostNetwork hostPID hostIPC; do
  if ! jq -e --arg field "$field" '.spec.template.spec[$field] != true' <<<"$board" >/dev/null 2>&1; then
    printf '%s\n' "deployment/board $field != true: ✗"
    failed=1
  fi
done
if ! jq -e 'all(.spec.template.spec.volumes[]?; .hostPath==null)' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board volumes hostPath = none: ✗'
  failed=1
fi
if ! jq -e '.spec.template.spec.securityContext.runAsNonRoot==true' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board runAsNonRoot = true: ✗'
  failed=1
fi
if ! jq -e '.spec.template.spec.securityContext.runAsUser==1000' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board runAsUser = 1000: ✗'
  failed=1
fi
if ! jq -e '.spec.template.spec.securityContext.seccompProfile.type=="RuntimeDefault"' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board seccompProfile.type = RuntimeDefault: ✗'
  failed=1
fi
for field in privileged allowPrivilegeEscalation readOnlyRootFilesystem drop add seccomp; do
  case "$field" in
    privileged) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; .securityContext.privileged != true)' ;;
    allowPrivilegeEscalation) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; .securityContext.allowPrivilegeEscalation==false)' ;;
    readOnlyRootFilesystem) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; .securityContext.readOnlyRootFilesystem==true)' ;;
    drop) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; (.securityContext.capabilities.drop // [] | index("ALL")) != null)' ;;
    add) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; (.securityContext.capabilities.add // [] | length)==0)' ;;
    seccomp) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; (.securityContext.seccompProfile.type // "RuntimeDefault")=="RuntimeDefault")' ;;
  esac
  if ! jq -e "$expr" <<<"$board" >/dev/null 2>&1; then
    printf '%s\n' "deployment/board containers securityContext $field: ✗"
    failed=1
  fi
done
if ! jq -e '[.spec.template.spec.volumes[]? | select(.name=="scratch" and .emptyDir!=null)] | length==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board volume scratch = emptyDir: ✗'
  failed=1
fi
if ! jq -e '[.spec.template.spec.containers[0].volumeMounts[]? | select(.name=="scratch" and .mountPath=="/tmp" and .readOnly!=true)] | length==1' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board worker scratch → /tmp writable: ✗'
  failed=1
fi
if ! jq -e 'all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; all(.volumeMounts[]?; (.name=="scratch" and .mountPath=="/tmp") or .readOnly==true))' <<<"$board" >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board worker writable mounts = [/tmp]: ✗'
  failed=1
fi
if ! kubectl exec --pod-running-timeout=2s deployment/board -- sh -c 'awk '\''$2=="/" {found=1; if ($4 ~ /(^|,)ro(,|$)/) ok=1} END {exit !(found && ok)}'\'' /proc/mounts' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board / mount = ro: ✗'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s deployment/board -- id -u 2>/dev/null)" = 1000; then
  printf '%s\n' 'deployment/board id -u = 1000: ✗'
  failed=1
fi
if ! kubectl exec --pod-running-timeout=2s deployment/board -- sh -c 'printf writable > /tmp/write-probe; test "$(cat /tmp/write-probe)" = writable' >/dev/null 2>&1; then
  printf '%s\n' 'deployment/board /tmp write/read: ✗'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s deployment/board -- wget -qO- -T 3 http://board:8080 2>/dev/null)" = north-109; then
  printf '%s\n' 'board:8080 = north-109: ✗'
  failed=1
fi
exit "$failed"
