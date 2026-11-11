set -euo pipefail
cd ~/quest
mkdir -p control
cat > control/README.md <<'DQ_CONTROL_MANUAL'
# en

Station control interface reference. This manual describes the interface, not the state of a service. Paths below are relative to `~/quest` on the workstation.

Request: `webhook-repair.json`, a regular UTF-8 JSON file of at most 4096 bytes, whose decoded object supports only the string property `action`. The only permitted value is `restore-path`: set the existing callback URL to the server path recorded in `admission-target.json`. The agent accepts no other action, target or additional field. It preserves the original webhook UID, namespace scope, CA, timeout and `failurePolicy` = `Fail` policy. It refuses a replaced server or changed protected configuration. The bay account has read-only access to the webhook configuration.

The agent reads requests during objective polling. A missing request does nothing. Repeating a valid request is idempotent. `webhook-agent-status.json` is initially present: `status` = `idle` means no processed request; `rejected` means invalid input; `restored` means the request was processed and the protected callback path was confirmed. These receipts do not assert that an application object is admissible or that a workload is healthy. Ownership or protected-configuration errors are reported by the poll without a success receipt.

# ru

Справочник интерфейса управления станцией. Здесь описан интерфейс, а не состояние сервиса. Пути ниже указаны относительно `~/quest` на workstation.

Запрос: `webhook-repair.json`, обычный файл JSON в UTF-8 размером не более 4096 байт, в декодированном объекте которого поддерживается только строковое свойство `action`. Разрешено только значение `restore-path`: установка в существующем URL callback пути сервера, указанного в `admission-target.json`. Другие действия, цели и дополнительные поля не принимаются. Агент сохраняет исходный UID webhook, область namespace, CA, timeout и политику `failurePolicy` = `Fail`. Замена сервера или изменение защищённой конфигурации приводят к отказу. Учётная запись Bay может только читать конфигурацию webhook.

Агент читает запросы при опросе целей. Отсутствие запроса ничего не меняет. Повтор корректного запроса идемпотентен. `webhook-agent-status.json` существует с начала задания: `status` = `idle` означает отсутствие обработанного запроса; `rejected` — неверный ввод; `restored` — запрос обработан и защищённый путь callback подтверждён. Квитанция не означает, что объект приложения допустим или нагрузка исправна. Ошибки владельца или защищённой конфигурации передаются через опрос без успешной квитанции.

# de

Referenz der Stationssteuerung. Dieses Handbuch beschreibt die Schnittstelle, nicht den Zustand eines Dienstes. Die folgenden Pfade sind relativ zu `~/quest` auf der Workstation.

Anfrage: `webhook-repair.json`, reguläre UTF-8-JSON-Datei mit höchstens 4096 Bytes, deren dekodiertes Objekt nur die Zeichenketteneigenschaft `action` unterstützt. Einziger erlaubter Wert: `restore-path`, um die bestehende Callback-URL auf den in `admission-target.json` angegebenen Serverpfad zu setzen. Andere Aktionen, Ziele oder Zusatzfelder werden nicht akzeptiert. Der Agent bewahrt die ursprüngliche Webhook-UID, den Namespace-Bereich, CA, Timeout und `failurePolicy` = `Fail`-Policy. Er verweigert ersetzte Server und geänderte geschützte Konfigurationen. Das Bay-Konto hat nur Lesezugriff auf die Webhook-Konfiguration.

Der Agent liest Anfragen bei der Zielabfrage. Ohne Anfrage erfolgt keine Änderung. Wiederholte gültige Anfragen sind idempotent. `webhook-agent-status.json` existiert von Anfang an: `status` = `idle` bedeutet keine verarbeitete Anfrage; `rejected` bedeutet ungültige Eingabe; `restored` bedeutet verarbeitete Anfrage und bestätigten geschützten Callback-Pfad. Diese Quittungen bestätigen weder die Zulässigkeit eines Anwendungsobjekts noch die Gesundheit eines Workloads. Eigentums- oder Schutzfehler werden ohne Erfolgsquittung über die Abfrage gemeldet.

# es

Referencia de la interfaz de control de la estación. Este manual describe la interfaz, no el estado de un servicio. Las rutas siguientes son relativas a `~/quest` en la workstation.

Solicitud: `webhook-repair.json`, archivo JSON UTF-8 regular de hasta 4096 bytes, cuyo objeto decodificado solo admite la propiedad de cadena `action`. El único valor permitido es `restore-path`: establecer en la URL de callback existente la ruta del servidor indicada en `admission-target.json`. No se aceptan otras acciones, destinos ni campos adicionales. El agente conserva el UID original del webhook, el ámbito de namespace, CA, timeout y la política `failurePolicy` = `Fail`. Rechaza servidores sustituidos o configuraciones protegidas modificadas. La cuenta de la bahía solo puede leer la configuración del webhook.

El agente lee las solicitudes durante el sondeo de objetivos. La ausencia de solicitud no cambia nada. Repetir una solicitud válida es idempotente. `webhook-agent-status.json` existe desde el inicio: `status` = `idle` indica que no hay solicitudes procesadas; `rejected`, entrada inválida; `restored`, solicitud procesada y ruta protegida confirmada. Los recibos no garantizan la admisibilidad de un objeto ni la salud de una carga. Los errores de propiedad o protección se comunican mediante el sondeo sin recibo de éxito.

# pl

Dokumentacja interfejsu sterowania stacją. Opisuje interfejs, a nie stan usługi. Poniższe ścieżki są względne wobec `~/quest` na workstation.

Żądanie: `webhook-repair.json`, zwykły plik JSON UTF-8 do 4096 bajtów, którego zdekodowany obiekt obsługuje tylko właściwość tekstową `action`. Jedyna dozwolona wartość to `restore-path`: ustawienie w istniejącym URL callback ścieżki serwera wskazanej w `admission-target.json`. Inne działania, cele i dodatkowe pola nie są akceptowane. Agent zachowuje pierwotny UID webhooka, zakres namespace, CA, timeout i politykę `failurePolicy` = `Fail`. Odrzuca zastąpiony serwer lub zmienioną chronioną konfigurację. Konto Bay ma tylko odczyt konfiguracji webhooka.

Agent czyta żądania podczas odpytywania celów. Brak żądania niczego nie zmienia. Powtarzanie poprawnego żądania jest idempotentne. `webhook-agent-status.json` istnieje od początku: `status` = `idle` oznacza brak przetworzonego żądania; `rejected` — nieprawidłowe dane; `restored` — przetworzone żądanie i potwierdzona chroniona ścieżka callback. Potwierdzenia nie gwarantują dopuszczalności obiektu ani zdrowia aplikacji. Błędy własności lub ochrony są zgłaszane przez odpytywanie bez potwierdzenia sukcesu.
DQ_CONTROL_MANUAL
printf '%s\n' 'Station control interface: see ~/quest/control/README.md' > .motd
printf '%s\n' '{"status":"idle"}' > webhook-agent-status.json
cat > board.yaml <<'DQ_ASSET'
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
            cpu: 10m
            memory: 8Mi
          limits:
            cpu: 200m
            memory: 32Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: route
          mountPath: /site
          readOnly: true
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          periodSeconds: 1
      volumes:
      - name: route
        configMap:
          name: route
          items:
          - key: route
            path: index.html
DQ_ASSET
python3 - board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f board.yaml
cat > service.yaml <<'DQ_ASSET'
apiVersion: v1
kind: Service
metadata:
  name: board
spec:
  selector:
    app: board
  ports:
  - name: http
    port: 8080
    targetPort: 8080
DQ_ASSET
python3 - service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f service.yaml
cat > client.yaml <<'DQ_ASSET'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
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
        - sleep
        - '3600'
        resources:
          requests:
            cpu: 10m
            memory: 8Mi
          limits:
            cpu: 200m
            memory: 32Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      terminationGracePeriodSeconds: 1
DQ_ASSET
python3 - client.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
kubectl apply -f client.yaml
kubectl rollout status deployment/client --timeout=90s
cat > route.yaml <<'DQ_ASSET'
apiVersion: v1
kind: ConfigMap
metadata:
  name: route
data:
  route: retired
DQ_ASSET
python3 - route.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
if kubectl apply -f route.yaml >/tmp/initial-admission.log 2>&1; then
 echo 'The broken webhook unexpectedly admitted the route' >&2; exit 1
fi
grep -E 'failed calling webhook|failed to call webhook' /tmp/initial-admission.log >/dev/null
