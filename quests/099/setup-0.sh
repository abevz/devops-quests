set -euo pipefail
cd ~/quest
source platform.env
mkdir -p control
cat > control/README.md <<'DQ_CONTROL_MANUAL'
# en

Station control interface reference. This manual describes the interface, not the state of a service. Paths below are relative to `~/quest` on the workstation.

Transport: synchronous JSON HTTP requests to `$VAULT_ADDR/v1`, authenticated with the supplied manager credential (`X-Vault-Token`). This credential has the following bounded operations only; it does not grant policy editing or direct secret reads.

`POST auth/token/create/rail-rotation` issues a token. All four fields are required: `policies` (array, only `rail-reader`); `ttl` (string, only `300s`); `renewable` (boolean, only `false`); `explicit_max_ttl` (string, only `600s`). The role also enforces the maximum lifetime and policy boundary. Successful responses contain private `auth.client_token`, its accessor and lease metadata. Do not display or publish credential responses.

`POST auth/token/revoke-accessor` revokes a token by accessor. The sole required field is `accessor` (string); only the accessor in the supplied `compromised-accessor` receipt is permitted. Success returns HTTP `204`; denied requests return `403`. Other malformed requests can return a non-success HTTP status with an `errors` array. There is no file request queue or polling agent for these HTTP operations. Each HTTP response describes that request, not application delivery.

`control/issuer-status.json` is an initial public `/sys/health` snapshot (`initialized`, `sealed`, `standby`); it is not updated after requests. Current health is available from `GET sys/health`. Token lookup and downstream access are separate observations; the initial health snapshot is not proof of either.

# ru

Справочник интерфейса управления станцией. Здесь описан интерфейс, а не состояние сервиса. Пути ниже указаны относительно `~/quest` на workstation.

Транспорт: синхронные HTTP-запросы JSON к `$VAULT_ADDR/v1` с предоставленными учётными данными manager (`X-Vault-Token`). Они разрешают только перечисленные ограниченные операции, без изменения политик или прямого чтения секретов.

`POST auth/token/create/rail-rotation` выпускает токен. Обязательны все четыре поля: `policies` (массив, только `rail-reader`); `ttl` (строка, только `300s`); `renewable` (логическое, только `false`); `explicit_max_ttl` (строка, только `600s`). Роль также ограничивает максимальный срок и политики. Успешный ответ содержит приватный `auth.client_token`, его accessor и метаданные срока действия. Не выводите и не публикуйте ответы с учётными данными.

`POST auth/token/revoke-accessor` отзывает токен по accessor. Единственное обязательное поле — `accessor` (строка); разрешён только accessor из предоставленной квитанции `compromised-accessor`. Успех возвращает HTTP `204`, отказ в доступе — `403`. Другой некорректный запрос может вернуть неуспешный HTTP-статус с массивом `errors`. У этих HTTP-операций нет файловой очереди или опрашивающего агента. HTTP-ответ описывает конкретный запрос, а не доставку приложения.

`control/issuer-status.json` — начальный публичный снимок `/sys/health` (`initialized`, `sealed`, `standby`); после запросов он не обновляется. Текущее состояние доступно через `GET sys/health`. Проверка токена и доступа потребителей — отдельные наблюдения; начальный снимок их не доказывает.

# de

Referenz der Stationssteuerung. Dieses Handbuch beschreibt die Schnittstelle, nicht den Zustand eines Dienstes. Die folgenden Pfade sind relativ zu `~/quest` auf der Workstation.

Transport: synchrone JSON-HTTP-Anfragen an `$VAULT_ADDR/v1` mit den bereitgestellten Manager-Zugangsdaten (`X-Vault-Token`). Sie erlauben nur die folgenden begrenzten Operationen, keine Richtlinienänderung oder direkten Secret-Lesezugriffe.

`POST auth/token/create/rail-rotation` stellt ein Token aus. Alle vier Felder sind erforderlich: `policies` (Array, nur `rail-reader`); `ttl` (Zeichenkette, nur `300s`); `renewable` (Boolesch, nur `false`); `explicit_max_ttl` (Zeichenkette, nur `600s`). Die Rolle begrenzt zusätzlich maximale Lebensdauer und Richtlinien. Erfolgsantworten enthalten das private `auth.client_token`, dessen Accessor und Laufzeitmetadaten. Antworten mit Zugangsdaten dürfen nicht angezeigt oder veröffentlicht werden.

`POST auth/token/revoke-accessor` widerruft ein Token anhand seines Accessors. Einziges Pflichtfeld: `accessor` (Zeichenkette); erlaubt ist nur der Accessor aus der bereitgestellten Quittung `compromised-accessor`. Erfolg liefert HTTP `204`, verweigerte Anfragen `403`. Andere ungültige Anfragen können einen Fehlerstatus mit einem `errors`-Array liefern. Für diese HTTP-Operationen gibt es weder Dateiwarteschlange noch Abfrageagenten. Jede HTTP-Antwort beschreibt die jeweilige Anfrage, nicht die Anwendungsauslieferung.

`control/issuer-status.json` ist eine anfängliche öffentliche `/sys/health`-Momentaufnahme (`initialized`, `sealed`, `standby`), die nach Anfragen nicht aktualisiert wird. Den aktuellen Zustand liefert `GET sys/health`. Tokenprüfung und nachgelagerter Zugriff sind getrennte Beobachtungen; die anfängliche Momentaufnahme beweist sie nicht.

# es

Referencia de la interfaz de control de la estación. Este manual describe la interfaz, no el estado de un servicio. Las rutas siguientes son relativas a `~/quest` en la workstation.

Transporte: solicitudes HTTP JSON síncronas a `$VAULT_ADDR/v1`, autenticadas con la credencial manager suministrada (`X-Vault-Token`). Solo permite las operaciones limitadas siguientes, sin editar políticas ni leer secretos directamente.

`POST auth/token/create/rail-rotation` emite un token. Los cuatro campos son obligatorios: `policies` (array, solo `rail-reader`); `ttl` (cadena, solo `300s`); `renewable` (booleano, solo `false`); `explicit_max_ttl` (cadena, solo `600s`). El rol también limita la duración máxima y las políticas. Las respuestas correctas contienen el `auth.client_token` privado, su accessor y metadatos de duración. No muestre ni publique respuestas con credenciales.

`POST auth/token/revoke-accessor` revoca un token por accessor. El único campo obligatorio es `accessor` (cadena); solo se permite el accessor del recibo suministrado `compromised-accessor`. El éxito devuelve HTTP `204`; las solicitudes denegadas, `403`. Otras solicitudes inválidas pueden devolver un estado de error con un array `errors`. Estas operaciones HTTP no tienen cola de archivos ni agente de sondeo. Cada respuesta HTTP describe esa solicitud, no la entrega de la aplicación.

`control/issuer-status.json` es una instantánea pública inicial de `/sys/health` (`initialized`, `sealed`, `standby`); no se actualiza tras las solicitudes. El estado actual está disponible en `GET sys/health`. La consulta del token y el acceso de consumidores son observaciones separadas; la instantánea inicial no los demuestra.

# pl

Dokumentacja interfejsu sterowania stacją. Opisuje interfejs, a nie stan usługi. Poniższe ścieżki są względne wobec `~/quest` na workstation.

Transport: synchroniczne żądania HTTP JSON do `$VAULT_ADDR/v1`, uwierzytelniane dostarczonym poświadczeniem manager (`X-Vault-Token`). Pozwala ono tylko na poniższe ograniczone operacje, bez edycji polityk i bezpośredniego odczytu sekretów.

`POST auth/token/create/rail-rotation` wydaje token. Wszystkie cztery pola są wymagane: `policies` (tablica, tylko `rail-reader`); `ttl` (tekst, tylko `300s`); `renewable` (wartość logiczna, tylko `false`); `explicit_max_ttl` (tekst, tylko `600s`). Rola ogranicza także maksymalny czas życia i polityki. Poprawna odpowiedź zawiera prywatny `auth.client_token`, jego accessor i metadane czasu życia. Nie wyświetlaj ani nie publikuj odpowiedzi z poświadczeniami.

`POST auth/token/revoke-accessor` unieważnia token przez accessor. Jedyne wymagane pole to `accessor` (tekst); dozwolony jest tylko accessor z dostarczonego potwierdzenia `compromised-accessor`. Sukces zwraca HTTP `204`, odmowa dostępu — `403`. Inne niepoprawne żądania mogą zwrócić status błędu z tablicą `errors`. Te operacje HTTP nie mają kolejki plików ani agenta odpytywania. Odpowiedź HTTP opisuje dane żądanie, a nie dostarczenie aplikacji.

`control/issuer-status.json` to początkowa publiczna migawka `/sys/health` (`initialized`, `sealed`, `standby`); nie jest aktualizowana po żądaniach. Aktualny stan udostępnia `GET sys/health`. Sprawdzenie tokena i dostępu odbiorców to osobne obserwacje; początkowa migawka ich nie dowodzi.
DQ_CONTROL_MANUAL
printf '%s\n' 'Station control interface: see ~/quest/control/README.md' > .motd
curl -fsS "$VAULT_ADDR/v1/sys/health" | jq '{initialized,sealed,standby}' > control/issuer-status.json
git -C repository remote add origin "$GIT_URL"
mkdir -p repository/manifests
cat > repository/manifests/board.yaml <<'DQ_ASSET'
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
        image: __PRIVATE_IMAGE__
        imagePullPolicy: Always
        command:
        - sh
        - -c
        - test "$ROUTE_SECRET" = north-secret; mkdir -p /tmp/site; printf "%s\n" "north-99" > /tmp/site/index.html;
          exec httpd -f -p 8080 -h /tmp/site
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
        env:
        - name: ROUTE_SECRET
          valueFrom:
            secretKeyRef:
              name: route-secret
              key: value
      imagePullSecrets:
      - name: registry-pull
DQ_ASSET
python3 - repository/manifests/board.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
mkdir -p repository/manifests
cat > repository/manifests/service.yaml <<'DQ_ASSET'
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
python3 - repository/manifests/service.yaml <<'DQ_IMAGE'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('__DQ_APP_IMAGE__',os.environ['DQ_APP_IMAGE']))
DQ_IMAGE
python3 - <<'IMAGE'
from pathlib import Path
import os
p=Path('repository/manifests/board.yaml');p.write_text(p.read_text().replace('__PRIVATE_IMAGE__',os.environ['PRIVATE_IMAGE']))
IMAGE
git -C repository add .
git -C repository commit -m 'Publish secret-backed private board'
git -C repository push origin main
git -C repository rev-parse HEAD > release-commit
jq -n --arg image "$PRIVATE_IMAGE" '{image:$image}' > private-release.json
cat > application.yaml <<'DQ_ASSET'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: board
spec:
  project: station
  source:
    repoURL: __GIT_URL__
    path: manifests
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: __NAMESPACE__
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
DQ_ASSET
python3 - <<'APP'
import os
from pathlib import Path
p=Path('application.yaml');p.write_text(p.read_text().replace('__GIT_URL__',os.environ['GIT_URL']).replace('__NAMESPACE__',os.environ['DQ_NAMESPACE']))
APP
kubectl apply -f application.yaml
