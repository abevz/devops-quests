set -euo pipefail
cd ~/quest
fleet_release=$(curl -fsS --max-time 3 "http://app1-${DQ_NAMESPACE#dq-}:8080/")
for host in app2 app3; do
  test "$(curl -fsS --max-time 3 "http://$host-${DQ_NAMESPACE#dq-}:8080/")" = "$fleet_release"
done
test "$fleet_release" = release-60
printf '%s\n' "$fleet_release" > fleet-release.txt
cat > release-config.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: relay-release
data:
  revision: retired
DQ_ASSET
kubectl apply -f release-config.yaml
kubectl get configmap relay-release -o jsonpath='{.metadata.uid}' > release-config-uid
cat > deployment.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: relay
spec:
  replicas: 1
  selector:
    matchLabels:
      app: relay
  template:
    metadata:
      labels:
        app: relay
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: ${DQ_APP_IMAGE}
        imagePullPolicy: Never
        command:
        - sh
        - -c
        - mkdir -p /tmp/www; echo signalrail >/tmp/www/index.html; httpd -f -p 8080 -h /tmp/www
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            memory: 64Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        env:
        - name: RELEASE
          value: retired
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - test "$RELEASE" = release-60
          periodSeconds: 2
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.yaml
kubectl apply -f deployment.yaml
