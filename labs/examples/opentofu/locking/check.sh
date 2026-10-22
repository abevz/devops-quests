#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
grep -q 'Error acquiring the state lock' competing.log
tofu plan -lock-timeout=1s -detailed-exitcode
