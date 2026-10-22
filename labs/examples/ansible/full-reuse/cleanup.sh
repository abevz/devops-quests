#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f results.json
rm -rf collections
rm -f collection-doc.json
find . -name result.log -delete
