#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
kubectl create namespace lab-helm-full --dry-run=client -o yaml | kubectl apply -f -
cat <<'PVC' | kubectl -n lab-helm-full apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: schema-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 32Mi}}
PVC
helm install demo ./chart -n lab-helm-full --set-string image="$DQ_APP_IMAGE" --wait --timeout=90s
kubectl -n lab-helm-full exec deployment/demo -- sh -c 'echo schema-v1 > /data/schema'
if helm upgrade demo ./chart -n lab-helm-full --set-string image=lab-missing:never --set runMigration=true --set-string migrationImage="$DQ_APP_IMAGE" --rollback-on-failure --timeout=30s > upgrade.log 2>&1; then echo 'Expected failed workload after successful migration'; exit 1; fi
