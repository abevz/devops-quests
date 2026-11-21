set -euo pipefail
cd ~/quest
expected=$(jq -er .recovery_id /run/dq/facts/1/recovered-release.json)
for host in app1 app2 app3; do
  peer="$host-${DQ_NAMESPACE#dq-}"
  test "$(timeout 4s ssh -n -o BatchMode=yes -o ConnectTimeout=3 -p 2222 "root@$peer" 'cat /srv/site/recovery-id')" = "$expected"
done
printf '%s\n' "$expected" > relay-handover-id
cat > relay-publication.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: relay-recovery
data:
  recovery-id: retired
DQ_ASSET
kubectl apply -f relay-publication.yaml
kubectl get configmap relay-recovery -o jsonpath='{.metadata.uid}' > relay-publication-uid
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
        - >-
          mkdir -p /tmp/www &&
          printf "%s\n" signalrail >/tmp/www/index.html &&
          ln -s /run/recovery/recovery-id /tmp/www/recovery-id &&
          exec httpd -f -p 8080 -h /tmp/www
        volumeMounts:
        - name: recovery-publication
          mountPath: /run/recovery
          readOnly: true
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
            - test "$RELEASE" = release-90
          periodSeconds: 2
      volumes:
      - name: recovery-publication
        configMap:
          name: relay-recovery
DQ_ASSET
sed -i 's|${DQ_APP_IMAGE}|'"$DQ_APP_IMAGE"'|g' deployment.yaml
kubectl apply -f deployment.yaml
