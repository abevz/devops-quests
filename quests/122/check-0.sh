set -euo pipefail
cd ~/quest
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" HEAD
test "$(git -C repository rev-parse HEAD)" != "$(cat /run/dq/facts/0/baseline-commit)"
test "$(git -C repository ls-remote origin refs/heads/main | cut -f1)" = "$(git -C repository rev-parse HEAD)"
git -C repository show HEAD:apps/child.json | jq -e '.kind=="Application" and .spec.source.path=="manifests" and .metadata.name=="board"' >/dev/null
bash wait-apps.sh
kubectl get application parent -o json | jq -e --arg uid "$(cat /run/dq/facts/0/parent-uid)" '.metadata.uid==$uid and .spec.source.path=="apps"' >/dev/null
kubectl get application board -o json | jq -e --arg ns "$DQ_NAMESPACE" '.spec.project=="station" and .spec.destination.namespace==$ns and .spec.source.path=="manifests" and (.metadata.annotations["argocd.argoproj.io/tracking-id"]==($ns+"_parent:argoproj.io/Application:"+$ns+"/board"))' >/dev/null
kubectl get deployment board -o json | jq -e '.status.readyReplicas==1' >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-122
