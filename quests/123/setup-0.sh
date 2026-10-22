set -euo pipefail
cd ~/quest
source platform.env
git -C repository remote add origin "$GIT_URL"
mkdir -p repository/stations/north
cat > repository/stations/north/board.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "north"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "north"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "north"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"north-123\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "32Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            }
          }
        ],
        "terminationGracePeriodSeconds": 1
      }
    }
  }
}
DQ_ASSET
python3 - repository/stations/north/board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p repository/stations/north
cat > repository/stations/north/service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "north"
  },
  "spec": {
    "selector": {
      "app": "north"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": 8080
      }
    ]
  }
}
DQ_ASSET
python3 - repository/stations/north/service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p repository/stations/south
cat > repository/stations/south/board.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "south"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "south"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "south"
        }
      },
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "runAsGroup": 1000,
          "fsGroup": 1000,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "worker",
            "image": "__DQ_APP_IMAGE__",
            "imagePullPolicy": "Never",
            "command": [
              "sh",
              "-c",
              "mkdir -p /tmp/site; printf \"%s\\n\" \"south-123\" > /tmp/site/index.html; exec httpd -f -p 8080 -h /tmp/site"
            ],
            "resources": {
              "requests": {
                "cpu": "10m",
                "memory": "8Mi"
              },
              "limits": {
                "cpu": "200m",
                "memory": "32Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            }
          }
        ],
        "terminationGracePeriodSeconds": 1
      }
    }
  }
}
DQ_ASSET
python3 - repository/stations/south/board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p repository/stations/south
cat > repository/stations/south/service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "south"
  },
  "spec": {
    "selector": {
      "app": "south"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": 8080
      }
    ]
  }
}
DQ_ASSET
python3 - repository/stations/south/service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
git -C repository add .
git -C repository commit -m 'Publish two independent station directories'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
cat > applicationset.json <<'DQ_ASSET'
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "ApplicationSet",
  "metadata": {
    "name": "station",
    "namespace": "__ARGO_NAMESPACE__"
  },
  "spec": {
    "goTemplate": true,
    "goTemplateOptions": [
      "missingkey=error"
    ],
    "generators": [
      {
        "list": {
          "elements": [
            {
              "station": "north"
            },
            {
              "station": "south"
            }
          ]
        }
      }
    ],
    "template": {
      "metadata": {
        "name": "{{.station}}"
      },
      "spec": {
        "project": "station",
        "source": {
          "repoURL": "__GIT_URL__",
          "targetRevision": "main",
          "path": "retired/{{.station}}"
        },
        "destination": {
          "server": "https://kubernetes.default.svc",
          "namespace": "__NAMESPACE__"
        },
        "syncPolicy": {
          "automated": {
            "prune": true,
            "selfHeal": true
          }
        }
      }
    },
    "syncPolicy": {
      "preserveResourcesOnDeletion": true
    }
  }
}
DQ_ASSET
python3 - <<'APPSET_TARGET'
import json,os
from pathlib import Path
p=Path('applicationset.json');s=p.read_text();target=json.loads(Path('appset-target.json').read_text())
p.write_text(s.replace('__ARGO_NAMESPACE__',target['namespace']).replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
APPSET_TARGET
cat > wait-apps.sh <<'DQ_ASSET'
#!/usr/bin/env bash
set -euo pipefail
ns=$(jq -r .namespace /run/dq/facts/0/appset-target.json)
uid=$(kubectl -n "$ns" get applicationset station -o jsonpath='{.metadata.uid}')
kubectl -n "$ns" get application north south -o json | jq -e --arg uid "$uid" --arg rev "$(cat /run/dq/facts/0/release-commit)" --arg bay "$DQ_NAMESPACE" --arg repo "$(jq -r .repoURL /run/dq/facts/0/appset-target.json)" '(.items|length)==2 and all(.items[]; .status.sync.status=="Synced" and .status.sync.revision==$rev and .status.health.status=="Healthy" and .spec.project=="station" and .spec.source.repoURL==$repo and .spec.source.path==("stations/"+.metadata.name) and .spec.destination.namespace==$bay and any(.metadata.ownerReferences[]; .uid==$uid and .kind=="ApplicationSet"))' >/dev/null
DQ_ASSET
