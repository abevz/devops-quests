set -euo pipefail
cd ~/quest
failed=0
daemonset=$(kubectl get daemonset relay -o json 2>/dev/null || true)
for field in hostNetwork hostPID hostIPC; do
  if ! jq -e --arg field "$field" '.spec.template.spec[$field] != true' <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay $field != true: ✗ [DQ:host_${field,,}]"
    failed=1
  fi
done
if ! jq -e 'all(.spec.template.spec.volumes[]?; .hostPath==null)' <<<"$daemonset" >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay volumes hostPath = none: ✗ [DQ:hostpath]'
  failed=1
fi
if ! jq -e '.spec.template.spec.securityContext.runAsNonRoot==true' <<<"$daemonset" >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay runAsNonRoot = true: ✗ [DQ:nonroot]'
  failed=1
fi
if ! jq -e '.spec.template.spec.securityContext.seccompProfile.type=="RuntimeDefault"' <<<"$daemonset" >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay seccompProfile.type = RuntimeDefault: ✗ [DQ:seccomp]'
  failed=1
fi
for field in privileged allowPrivilegeEscalation drop add; do
  case "$field" in
    privileged) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; .securityContext.privileged!=true)' ;;
    allowPrivilegeEscalation) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; .securityContext.allowPrivilegeEscalation==false)' ;;
    drop) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; (.securityContext.capabilities.drop // [] | index("ALL")) != null)' ;;
    add) expr='all((.spec.template.spec.containers+(.spec.template.spec.initContainers//[]))[]; (.securityContext.capabilities.add // [] | length)==0)' ;;
  esac
  if ! jq -e "$expr" <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay containers securityContext $field: ✗ [DQ:security_${field,,}]"
    failed=1
  fi
done
if ! jq -e '.spec.template.spec.nodeSelector=={"kubernetes.io/os":"linux"}' <<<"$daemonset" >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay nodeSelector = {kubernetes.io/os:linux}: ✗ [DQ:node_selector]'
  failed=1
fi
for field in desiredNumberScheduled numberReady numberAvailable; do
  if ! jq -e --arg field "$field" '.status[$field]==1' <<<"$daemonset" >/dev/null 2>&1; then
    printf '%s\n' "daemonset/relay $field = 1: ✗ [DQ:status_${field,,}]"
    failed=1
  fi
done
uid=$(jq -r '.metadata.uid // ""' <<<"$daemonset" 2>/dev/null || true)
if ! test -n "$uid" || ! kubectl get pods -l app=relay -o json 2>/dev/null | jq -e --arg node "$DQ_NODE_NAME" --arg uid "$uid" 'any(.items[];.metadata.deletionTimestamp==null and .spec.nodeName==$node and any(.metadata.ownerReferences[]?;.kind=="DaemonSet" and .uid==$uid and .controller==true) and any(.status.containerStatuses[]?;.ready==true))' >/dev/null 2>&1; then
  printf '%s\n' 'daemonset/relay owned Ready Pod on DQ_NODE_NAME: ✗ [DQ:owned]'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s daemonset/relay -- wget -qO- -T 3 http://127.0.0.1:8080 2>/dev/null)" = north-103; then
  printf '%s\n' 'daemonset/relay Pod 127.0.0.1:8080 = north-103: ✗ [DQ:local_http]'
  failed=1
fi
if ! test "$(kubectl exec --pod-running-timeout=2s daemonset/relay -- wget -qO- -T 3 http://relay:8080 2>/dev/null)" = north-103; then
  printf '%s\n' 'relay:8080 = north-103: ✗ [DQ:service_http]'
  failed=1
fi
exit "$failed"
