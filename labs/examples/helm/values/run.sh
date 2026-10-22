#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
helm lint ./chart
helm template demo ./chart -f base.yaml -f override.yaml > merged.yaml
helm template demo ./chart --set-string message=true > string.yaml
helm template demo ./chart --set-json 'features=["x","y"]' > json.yaml
helm template demo ./chart --set-file message=message.txt > file.yaml
