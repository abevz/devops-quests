set -euo pipefail
cd ~/quest
source platform.env
kubectl get application board -o json | jq -e --arg url "$GIT_URL" --arg revision "$(cat /run/dq/facts/0/baseline-commit)" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .status.sync.status=="Synced" and .status.sync.revision==$revision and .spec.syncPolicy.automated.selfHeal==true' >/dev/null
kubectl get deployment board -o json | jq -e '.spec.template.spec.imagePullSecrets==[{name:"registry-pull"}] and .spec.template.spec.containers[0].imagePullPolicy=="Always"' >/dev/null
