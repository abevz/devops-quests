#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
kubectl create namespace lab-helm --dry-run=client -o yaml | kubectl apply -f -
helm install demo ./chart -n lab-helm --set-string image="$DQ_APP_IMAGE" --wait --timeout=90s
helm upgrade demo ./chart -n lab-helm --set-string image="$DQ_APP_IMAGE" --set-string message=second --wait --timeout=90s
helm history demo -n lab-helm
