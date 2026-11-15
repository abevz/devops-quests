set -euo pipefail
cd ~/quest
cat > board-fixed.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: board
spec:
  replicas: 1
  selector:
    matchLabels:
      app: board
  template:
    metadata:
      labels:
        app: board
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: __DQ_APP_IMAGE__
        imagePullPolicy: Never
        command:
        - httpd
        - -f
        - -p
        - '8080'
        - -h
        - /site
        resources:
          requests:
            cpu: 100m
            memory: 16Mi
          limits:
            cpu: 300m
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: route
          mountPath: /site
          readOnly: true
      terminationGracePeriodSeconds: 1
      volumes:
      - name: route
        emptyDir: {}
      - name: source
        configMap:
          name: route-source
      initContainers:
      - name: prepare-route
        image: __DQ_APP_IMAGE__
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - cp /source/index.html /site/index.html
        resources:
          requests:
            cpu: 10m
            memory: 8Mi
          limits:
            memory: 16Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: source
          mountPath: /source
          readOnly: true
        - name: route
          mountPath: /site
DQ_ASSET
python3 -I - <<'DQ_CPU_REFERENCE'
import os
from pathlib import Path
p=Path('board-fixed.yaml');p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_CPU_REFERENCE
kubectl apply -f board-fixed.yaml
kubectl rollout status deployment/board --timeout=90s
