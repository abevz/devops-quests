set -euo pipefail
cd ~/quest
kubectl scale deployment relay --replicas=0
kubectl delete pvc spool --wait=true
cat > spool-fixed.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "PersistentVolumeClaim",
  "metadata": {
    "name": "spool"
  },
  "spec": {
    "accessModes": [
      "ReadWriteOnce"
    ],
    "storageClassName": "standard",
    "resources": {
      "requests": {
        "storage": "8Mi"
      }
    }
  }
}
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' spool-fixed.json
kubectl apply -f spool-fixed.json
kubectl scale deployment relay --replicas=1
kubectl rollout status deployment/relay --timeout=90s
