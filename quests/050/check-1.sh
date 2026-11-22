set -euo pipefail
cd ~/quest
failed=0
set +e
(
set -e
set +e
(
set -e
source platform.env
expected=$(git -C repository ls-remote origin refs/heads/main | cut -f1)
kubectl get application station -o json | jq -e --arg repo "$GIT_URL" --arg ns "$DQ_NAMESPACE" --arg rev "$expected" '.spec.project=="station" and .spec.source.repoURL==$repo and (.spec.source.path | (startswith("/")|not) and ([splits("/") | select(.!="" and .!=".")]==["manifests"])) and .spec.source.targetRevision=="main" and .spec.destination.namespace==$ns and ((((((.spec.destination.server=="https://kubernetes.default.svc" and ((.spec.destination.name // "")=="" or .spec.destination.name=="in-cluster")) or ((.spec.destination.server // "")=="" and .spec.destination.name=="in-cluster")) and ((.spec.destination.name // "")=="" or .spec.destination.name=="in-cluster")) or ((.spec.destination.server // "")=="" and .spec.destination.name=="in-cluster")) and ((.spec.destination.name // "")=="" or .spec.destination.name=="in-cluster")) or ((.spec.destination.server // "")=="" and .spec.destination.name=="in-cluster")) and .status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Private Git delivery could not be verified: ✗ [DQ:argo_release]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
source platform.env
expected=$(git -C repository ls-remote origin refs/heads/main | cut -f1)
git -C repository fetch origin main >/dev/null 2>&1
git -C repository merge-base --is-ancestor "$(cat baseline-commit)" "$expected"
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Private Git delivery could not be verified: ✗ [DQ:remote_ancestry]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
kubectl rollout status deployment/board --timeout=3s >/dev/null
kubectl get deployment board -o json | jq -e '.metadata.annotations["argocd.argoproj.io/tracking-id"]|length>0' >/dev/null
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Private Git delivery could not be verified: ✗ [DQ:controller_tracking]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
(
set -e
set +e
(
set -e
test "$(kubectl exec deployment/board -c worker -- wget -qO- http://127.0.0.1:8080)" = north-50
)
code=$?
set -e
if [ "$code" -ne 0 ]; then
  printf '%s\n' 'Private Git delivery could not be verified: ✗ [DQ:delivery_http]' >&2
  exit "$code"
fi
)
[ $? -eq 0 ] || failed=1
exit "$failed"
