set -euo pipefail
cd ~/quest
cat > board.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "board"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "board"
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
              "mkdir -p /tmp/site; echo north-130 > /tmp/site/index.html; httpd -p 8080 -h /tmp/site; while :; do :; done"
            ],
            "resources": {
              "requests": {
                "cpu": "0",
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
python3 - board.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.json
cat > service.json <<'DQ_ASSET'
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "selector": {
      "app": "board"
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
python3 - service.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.json
cat > client.json <<'DQ_ASSET'
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "client"
  },
  "spec": {
    "replicas": 1,
    "selector": {
      "matchLabels": {
        "app": "client"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "client"
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
              "sleep",
              "3600"
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
python3 - client.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.json
cat > hpa.json <<'DQ_ASSET'
{
  "apiVersion": "autoscaling/v2",
  "kind": "HorizontalPodAutoscaler",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "scaleTargetRef": {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "name": "board"
    },
    "minReplicas": 1,
    "maxReplicas": 2,
    "metrics": [
      {
        "type": "Resource",
        "resource": {
          "name": "cpu",
          "target": {
            "type": "Utilization",
            "averageUtilization": 50
          }
        }
      }
    ]
  }
}
DQ_ASSET
python3 - hpa.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f hpa.json
kubectl rollout status deployment/board --timeout=90s
kubectl rollout status deployment/client --timeout=90s
source book-components.env
cat > gateway.json <<'DQ_ASSET'
{
  "apiVersion": "gateway.networking.k8s.io/v1",
  "kind": "Gateway",
  "metadata": {
    "name": "station"
  },
  "spec": {
    "gatewayClassName": "__GATEWAY_CLASS__",
    "listeners": [
      {
        "name": "web",
        "hostname": "north.station.internal",
        "protocol": "HTTP",
        "port": 8000,
        "allowedRoutes": {
          "namespaces": {
            "from": "Same"
          }
        }
      }
    ]
  }
}
DQ_ASSET
python3 - gateway.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
cat > ingress-policy.json <<'DQ_ASSET'
{
  "apiVersion": "networking.k8s.io/v1",
  "kind": "NetworkPolicy",
  "metadata": {
    "name": "board-ingress"
  },
  "spec": {
    "podSelector": {
      "matchLabels": {
        "app": "board"
      }
    },
    "policyTypes": [
      "Ingress"
    ],
    "ingress": [
      {
        "from": [
          {
            "namespaceSelector": {
              "matchLabels": {
                "kubernetes.io/metadata.name": "__COMPONENT_NAMESPACE__"
              }
            },
            "podSelector": {
              "matchLabels": {
                "app": "gateway"
              }
            }
          }
        ],
        "ports": [
          {
            "port": 8080,
            "protocol": "TCP"
          }
        ]
      }
    ]
  }
}
DQ_ASSET
python3 - ingress-policy.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
sed -i "s/__GATEWAY_CLASS__/$GATEWAY_CLASS/g" gateway.json
sed -i "s/__COMPONENT_NAMESPACE__/dq-book-${DQ_NAMESPACE#dq-}/g" ingress-policy.json
kubectl apply -f gateway.json
kubectl apply -f ingress-policy.json
printf '{"class":"%s","url":"%s","namespace":"dq-book-%s"}
' "$GATEWAY_CLASS" "$GATEWAY_URL" "${DQ_NAMESPACE#dq-}" > gateway-target.json
cat > route.json <<'DQ_ASSET'
{
  "apiVersion": "gateway.networking.k8s.io/v1",
  "kind": "HTTPRoute",
  "metadata": {
    "name": "board"
  },
  "spec": {
    "parentRefs": [
      {
        "name": "station",
        "sectionName": "web"
      }
    ],
    "hostnames": [
      "north.station.internal"
    ],
    "rules": [
      {
        "matches": [
          {
            "path": {
              "type": "PathPrefix",
              "value": "/"
            }
          }
        ],
        "backendRefs": [
          {
            "name": "board",
            "port": 8080
          }
        ]
      }
    ]
  }
}
DQ_ASSET
python3 - route.json <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f route.json
