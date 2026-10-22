#!/bin/bash
set -euo pipefail
case "$(kubectl config current-context)" in kind-dq-lab-*) ;; *) echo "Use this example inside its Lab" >&2; exit 1 ;; esac
cd "$(dirname "$0")"
helm uninstall demo -n lab-helm --ignore-not-found
kubectl delete namespace lab-helm --ignore-not-found --wait=true
rm -f failure.log
