set -euo pipefail
cd ~/quest
source platform.env
kubectl get application board -o json | jq -e --arg rev "$(cat /run/dq/facts/0/baseline-commit)" --arg url "$GIT_URL" '.spec.source.repoURL==$url and .spec.source.path=="manifests" and .spec.source.targetRevision=="main" and .spec.syncPolicy.automated.selfHeal==true and .spec.syncPolicy.automated.prune==true and .status.sync.status=="Synced" and .status.sync.revision==$rev' >/dev/null
