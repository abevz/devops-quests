#!/bin/bash
set -euo pipefail
kubectl delete namespace lab-probes --ignore-not-found --wait=true
