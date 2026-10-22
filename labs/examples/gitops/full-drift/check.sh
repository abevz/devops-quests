#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
source "$HOME/lab/platform.env"
app=lab-guide
state() { kubectl -n "$LAB_NAMESPACE" get application "$app" -o json | jq '{sync:.status.sync.status,health:.status.health.status,operation:.status.operationState.phase}'; }
refresh() { kubectl -n "$LAB_NAMESPACE" annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite; }
sync() {
 kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"operation":{"sync":{"prune":true}}}'
 kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.operationState.phase}'=Succeeded application/"$app" --timeout=150s
}
kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true,"selfHeal":false,"prune":false}}}}'
kubectl -n "$LAB_NAMESPACE" patch configmap lab-settings --type merge -p '{"data":{"version":"manual"}}'
refresh
kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.sync.status}'=OutOfSync application/"$app" --timeout=60s
[ "$(kubectl -n "$LAB_NAMESPACE" get cm lab-settings -o jsonpath='{.data.version}')" = manual ]
kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true,"selfHeal":true,"prune":false}}}}'
for try in $(seq 1 90); do
 test "$(kubectl -n "$LAB_NAMESPACE" get cm lab-settings -o jsonpath='{.data.version}')" = v1 && break
 sleep 1
done
[ "$(kubectl -n "$LAB_NAMESPACE" get cm lab-settings -o jsonpath='{.data.version}')" = v1 ]
(cd repo; git rm manifests/settings.yaml; git commit -m 'Remove settings from desired state'; git push origin HEAD:main)
refresh
# Verify the controller has observed the new Git revision, not just elapsed time.
revision=$(cd repo; git rev-parse HEAD)
kubectl -n "$LAB_NAMESPACE" wait --for=jsonpath='{.status.sync.revision}'="$revision" application/"$app" --timeout=120s
kubectl -n "$LAB_NAMESPACE" get cm lab-settings >/dev/null
kubectl -n "$LAB_NAMESPACE" patch application "$app" --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true}}}}'
refresh
kubectl -n "$LAB_NAMESPACE" wait --for=delete configmap/lab-settings --timeout=120s
echo 'Self-heal restored drift; prune separately removed the deleted desired object.'

cat <<'OBJECT' > owner.yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: lab-field-owner}
data: {value: first}
OBJECT
kubectl -n "$LAB_NAMESPACE" apply --server-side --field-manager=lab-first -f owner.yaml
sed -i 's/value: first/value: second/' owner.yaml
if kubectl -n "$LAB_NAMESPACE" apply --server-side --field-manager=lab-second -f owner.yaml > conflict.log 2>&1; then echo 'Expected field ownership conflict'; exit 1; fi
grep -qi conflict conflict.log
kubectl -n "$LAB_NAMESPACE" apply --server-side --field-manager=lab-second --force-conflicts -f owner.yaml
[ "$(kubectl -n "$LAB_NAMESPACE" get cm lab-field-owner -o jsonpath='{.data.value}')" = second ]
echo 'A separate SSA field owner caused a real conflict; explicit ownership transfer resolved it.'
