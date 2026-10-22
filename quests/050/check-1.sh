set -euo pipefail
cd ~/quest
source platform.env
expected=$(git -C repository ls-remote origin refs/heads/main | cut -f1)
kubectl get application station -o json | jq -e --arg repo "$GIT_URL" --arg ns "$DQ_NAMESPACE" --arg rev "$expected" '.spec.project=="station" and .spec.source.repoURL==$repo and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .spec.destination.namespace==$ns and .spec.destination.server=="https://kubernetes.default.svc" and .status.sync.revision==$rev and .status.sync.status=="Synced" and .status.health.status=="Healthy"' >/dev/null
git -C repository fetch origin main >/dev/null 2>&1
git -C repository merge-base --is-ancestor "$(cat baseline-commit)" "$expected"
kubectl rollout status deployment/board --timeout=3s >/dev/null
kubectl get deployment board -o json | jq -e '.metadata.annotations["argocd.argoproj.io/tracking-id"]|length>0' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- http://127.0.0.1:8080)" = north-50
