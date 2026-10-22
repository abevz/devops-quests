#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
tofu init -input=false
rm -f lock-ready
# Ensure the slow operation actually needs to run, even on a repeated experiment.
tofu apply -auto-approve -replace=terraform_data.slow > first.log 2>&1 &
pid=$!
trap 'wait "$pid" || true' EXIT
for try in $(seq 1 80); do test -f lock-ready && break; sleep .1; done
test -f lock-ready
if tofu plan -lock-timeout=1s > competing.log 2>&1; then echo 'Expected state lock refusal'; exit 1; fi
wait "$pid"
trap - EXIT
