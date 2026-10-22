#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f merged.yaml number.yaml string.yaml json.yaml file.yaml escaped.yaml null.yaml malformed.log
