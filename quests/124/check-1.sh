set -euo pipefail
cd ~/quest
volume=$(jq -r .volume /run/dq/facts/0/volume-contract.json)
uid=$(jq -r .pv_uid /run/dq/facts/0/volume-contract.json)
kubectl get pv "$volume" -o json | jq -e --arg uid "$uid" --arg volume "$volume" '.metadata.uid==$uid and .spec.storageClassName==$volume and .spec.persistentVolumeReclaimPolicy=="Retain" and .status.phase=="Bound"' >/dev/null
claim_uid=$(kubectl get pvc ledger -o jsonpath='{.metadata.uid}')
kubectl get pv "$volume" -o json | jq -e --arg claim "$claim_uid" '.spec.claimRef.uid==$claim' >/dev/null
test "$(kubectl exec deployment/client -- wget -qO- -T 3 http://board:8080)" = north-124
test "$claim_uid" != "$(cat /run/dq/facts/0/original-claim-uid)"
