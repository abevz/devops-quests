set -euo pipefail
cd ~/quest
source platform.env
git -C repository fetch origin main >/dev/null 2>&1
test "$(git -C repository rev-parse origin/main)" = "$(cat release-commit)"
kubectl get application board -o json | jq -e --arg rev "$(cat release-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.health.status=="Healthy" and .status.sync.revision==$rev' >/dev/null
kubectl rollout status deployment/board --timeout=3s >/dev/null
test "$(kubectl exec deployment/board -- wget -qO- -T 3 http://board:8080)" = north-91
image=$(jq -er .image /run/dq/facts/0/release-evidence.json)
commit=$(jq -er .commit /run/dq/facts/0/release-evidence.json)
test "$commit" != "$(cat release-commit)"
git -C repository merge-base --is-ancestor "$commit" origin/main
test "$(git -C repository show "$commit:site/index.html")" = north-91
jq -e --arg image "$image" --arg commit "$commit" --arg repo "$GIT_URL" '.=={image:$image,commit:$commit,repo:$repo}' provenance.json >/dev/null
digest=${image##*@}
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/$digest" > /tmp/actual-manifest.json
test "sha256:$(sha256sum /tmp/actual-manifest.json | cut -d' ' -f1)" = "$digest"
config=$(jq -er .config.digest /tmp/actual-manifest.json)
curl -fsS --cacert /run/dq/facts/0/registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "https://$REGISTRY/v2/parcel/blobs/$config" | jq -e --arg rev "$commit" '.config.Labels["org.opencontainers.image.revision"]==$rev' >/dev/null
kubectl get deployment board -o json | jq -e --arg image "$image" '.spec.template.spec.containers[0].image==$image' >/dev/null
kubectl get pods -l app=board -o json | jq -e --arg digest "$digest" 'any(.items[];any(.status.containerStatuses[]?;.ready==true and (.imageID|contains($digest))))' >/dev/null
