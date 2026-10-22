#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f results.json
find . -name result.log -delete
