#!/bin/bash
set -euo pipefail
ns=lab-probes
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ns" delete pod probe --ignore-not-found --wait=true
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: probe, namespace: $ns}
spec:
  containers:
  - name: app
    image: $DQ_APP_IMAGE
    imagePullPolicy: Never
    command: [sh, -c, 'touch /tmp/live; sleep 3600']
    startupProbe:
      exec: {command: [test, -e, /tmp/live]}
      periodSeconds: 1
    readinessProbe:
      exec: {command: [test, -e, /tmp/ready]}
      periodSeconds: 1
    livenessProbe:
      exec: {command: [test, -e, /tmp/live]}
      periodSeconds: 1
      failureThreshold: 3
YAML
kubectl -n "$ns" wait --for=jsonpath='{.status.phase}'=Running pod/probe --timeout=90s
kubectl -n "$ns" get pod probe
