#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
helm template demo ./chart -f first.yaml -f second.yaml > merged.yaml
helm template demo ./chart --set replicaCount=3 > number.yaml
helm template demo ./chart -f first.yaml -f second.yaml --set replicaCount=5 > cli-last.yaml
helm template demo ./chart --set 'x=12,y=true,z=1.10' > inferred.yaml
helm template demo ./chart --set-string x=012 --set x=7 > flag-groups.yaml
helm template demo ./chart --set-string replicaCount=3 > string.yaml
helm template demo ./chart --set-json 'config={"port":8080,"enabled":true,"names":["a","b"]}' > json.yaml
helm template demo ./chart --set-file certificate=certificate.txt > file.yaml
helm template demo ./chart --set 'literal=a\,b' --set 'annotations.example\.com/key=value' > escaped.yaml
helm template demo ./chart --set probe.httpGet=null --set-json 'probe.exec={"command":["true"]}' > null.yaml
helm template demo ./chart --set 'probe.httpGet=null,probe.exec.command[0]=true' > boolean-command.yaml
if helm template demo ./chart --set literal=a,b > malformed.log 2>&1; then echo 'Expected comma parsing failure'; exit 1; fi
