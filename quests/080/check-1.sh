set -euo pipefail
cd ~/quest
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-80
image=$(jq -er .image /run/dq/facts/0/private-release.json)
digest=$(printf %s "$image" | cut -d@ -f2)
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
test "$(cat release-commit)" != "$(cat /run/dq/facts/0/baseline-commit)"
git -C repository merge-base --is-ancestor "$(cat /run/dq/facts/0/baseline-commit)" origin/main
git -C repository show origin/main:manifests/board.json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image and .spec.template.spec.containers[0].imagePullPolicy=="Always" and .spec.template.spec.imagePullSecrets==[{name:"registry-pull"}]' >/dev/null
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image and .spec.template.spec.containers[0].imagePullPolicy=="Always"' >/dev/null
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[];.metadata.deletionTimestamp==null and any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null
curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" >/dev/null
kubectl get application board -o json | jq -e '.spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true' >/dev/null
