#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
helm uninstall demo -n lab-helm-full --ignore-not-found
kubectl delete namespace lab-helm-full --ignore-not-found --wait=true
