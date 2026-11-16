"""Host provisioning for actual cached Vault consumers in disposable training bays."""
import hashlib
import json
import re

APPLICATION = "\"\"\"Provided cached application. It reads inputs; it never repairs Vault or other services.\"\"\"\nimport hashlib\nimport json\nimport signal\nimport sys\nimport urllib.error\nimport urllib.parse\nimport urllib.request\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\nfrom pathlib import Path\n\nmode, filename, port = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3])\nstate = {\"ready\": False, \"error\": \"NotObserved\"}\nopener = urllib.request.build_opener(urllib.request.ProxyHandler({}))\n\n\ndef base_url(value):\n    parsed = urllib.parse.urlsplit(value)\n    if (parsed.scheme not in (\"http\", \"https\") or not parsed.hostname\n            or parsed.username is not None or parsed.password is not None\n            or parsed.query or parsed.fragment):\n        raise ValueError(\"base URL\")\n    return value.rstrip(\"/\")\n\n\ndef refresh(*_):\n    global state\n    try:\n        if filename.stat().st_size > 4096:\n            raise ValueError(\"configuration size\")\n        config = json.loads(filename.read_text())\n        if mode == \"vault\":\n            if set(config) != {\"url\", \"path\", \"token_file\"}:\n                raise ValueError(\"configuration fields\")\n            source = base_url(config[\"url\"])\n            credential = Path(config[\"token_file\"])\n            if credential.stat().st_size > 4096:\n                raise ValueError(\"credential size\")\n            token = credential.read_text().strip()\n            path = config[\"path\"].lstrip(\"/\")\n            request = urllib.request.Request(source + \"/v1/\" + path, headers={\"X-Vault-Token\": token})\n            with opener.open(request, timeout=2) as response:\n                payload = json.load(response)\n            value = payload[\"data\"][\"data\"][\"value\"]\n            version = payload[\"data\"][\"metadata\"][\"version\"]\n            if not isinstance(value, str) or type(version) is not int or version < 1:\n                raise ValueError(\"publication schema\")\n            state = {\"ready\": True, \"kind\": \"vault\", \"source\": source,\n                     \"path\": urllib.parse.urlsplit(path).path,\n                     \"value_sha256\": hashlib.sha256(value.encode()).hexdigest(), \"version\": version}\n        elif mode == \"upstream\":\n            if set(config) != {\"upstream\"}:\n                raise ValueError(\"configuration fields\")\n            source = base_url(config[\"upstream\"])\n            with opener.open(source + \"/\", timeout=2) as response:\n                payload = json.load(response)\n            if (payload.get(\"ready\") is not True or not isinstance(payload.get(\"value_sha256\"), str)\n                    or len(payload[\"value_sha256\"]) != 64 or type(payload.get(\"version\")) is not int):\n                raise ValueError(\"upstream schema\")\n            state = {\"ready\": True, \"kind\": \"consumer\", \"source\": source,\n                     \"value_sha256\": payload[\"value_sha256\"], \"version\": payload[\"version\"]}\n        else:\n            raise ValueError(\"application role\")\n        print(\"refresh ready\", flush=True)\n    except Exception as error:\n        state = {\"ready\": False, \"error\": type(error).__name__}\n        if isinstance(error, urllib.error.HTTPError):\n            state[\"status\"] = error.code\n        print(\"refresh failed: \" + type(error).__name__, flush=True)\n\n\nclass Handler(BaseHTTPRequestHandler):\n    def do_GET(self):\n        if self.path not in (\"/\", \"/status\"):\n            self.send_error(404)\n            return\n        body = json.dumps(state, sort_keys=True).encode()\n        self.send_response(200 if self.path == \"/status\" or state[\"ready\"] else 503)\n        self.send_header(\"Content-Type\", \"application/json\")\n        self.send_header(\"Content-Length\", str(len(body)))\n        self.end_headers()\n        self.wfile.write(body)\n\n    def log_message(self, *_):\n        pass\n\n\nsignal.signal(signal.SIGHUP, refresh)\nrefresh()\nHTTPServer((\"127.0.0.1\", port), Handler).serve_forever()\n"

SNAPSHOT = r"""
import hashlib,json
from pathlib import Path
result={}
for role in ROLES:
 pid=int(Path(role+'/application.pid').read_text())
 proc=Path('/proc')/str(pid)
 status=dict(line.split(':',1) for line in (proc/'status').read_text().splitlines() if ':' in line)
 result[role]={'pid':pid,'start':(proc/'stat').read_text().rsplit(') ',1)[1].split()[19],
 'command':(proc/'cmdline').read_bytes().hex(),
 'status':{k:status[k].strip() for k in ('Uid','Gid','Groups','CapEff','NoNewPrivs')}}
result['program_sha256']=hashlib.sha256(Path('provided-vault-consumer.py').read_bytes()).hexdigest()
print(json.dumps(result))
"""


def audit_metadata(raw):
    """Export only actual read-denial identifiers, never arbitrary backend fields."""
    result = []
    for line in raw.splitlines():
        event = json.loads(line)
        request = event.get("request", {})
        if (
            event.get("type") == "response"
            and "permission denied" in str(event.get("error", ""))
            and request.get("operation") == "read"
            and request.get("path") in {"secret/data/dispatch", "secret/dispatch"}
            and re.fullmatch(r"[a-f0-9-]{36}", request.get("id", ""))
        ):
            result.append({
                "request_id": request["id"], "path": request["path"],
                "operation": "read", "reason": "permission_denied",
            })
    return result


MANUAL = '# en\n\nThe provided program is a read-only cached HTTP application, not a repair or synchronization tool. Configuration is read at startup and on SIGHUP; requests do not refresh it. Its PID is in application.pid. Send SIGHUP to the existing PID after changing configuration. Do not restart, replace, edit the program, or alter process privileges. The files source.json, application.pid and application.log are relative to each application directory. GET /status always returns metadata; GET / returns 200 only for an adopted publication, otherwise 503. Metadata contains readiness, source, version and SHA-256, never the secret or token. Logs contain error classes; status metadata also contains the upstream HTTP error code. Failed refresh replaces the cached publication with failure. The primary endpoint is http://127.0.0.1:18081; the downstream endpoint, when supplied, is http://127.0.0.1:18082. Vault configuration has exactly url (base address), path (API path without /v1/), token_file (private UTF-8 credential file, relative to ~/quest or absolute). The supplied platform environment provides distinct reader and manager credentials. Upstream configuration has exactly upstream (the base URL of another application). JSON and credentials are limited to 4096 bytes. The downstream application fetches the upstream publication on its own refresh; recovering the upstream alone does not refresh its cache. The original contract records process identity, approved Vault address, API path, reader credential fingerprint, publication digest and version; it contains no credentials. For audit exercises, consumer-audit.json contains only request_id, path, operation and reason from actual denied reads; consumer/initial-observation.json records the initial application request path, operation and HTTP status. consumer-incident.json is an object with baseline and application, each containing the corresponding four-field audit event. Never copy raw authentication, audit payloads or secret values into incident files.\n\nWhere a quest requires the narrow reader boundary, its negative capability probes target secret/data/other and sys/audit: both must report [deny]. These two probes do not prove denial on every Vault path.\n\n# ru\n\nПрограмма — HTTP-приложение с кешем и доступом только на чтение, а не средство ремонта или синхронизации. Конфигурация читается при запуске и по SIGHUP; HTTP-запросы её не обновляют. PID записан в application.pid. После изменения конфигурации отправьте SIGHUP существующему PID. Не перезапускайте и не заменяйте процесс, не меняйте программу или привилегии. source.json, application.pid и application.log находятся в каталоге каждого приложения. GET /status всегда возвращает метаданные; GET / возвращает 200 только при принятой публикации, иначе 503. Метаданные содержат готовность, источник, версию и SHA-256, но не секрет или токен. Журнал содержит классы ошибок, статус — также HTTP-код ошибки источника. Неуспешное обновление заменяет кеш состоянием ошибки. Основной адрес: http://127.0.0.1:18081; адрес второго приложения, если оно выдано: http://127.0.0.1:18082. Конфигурация Vault содержит ровно url (базовый адрес), path (путь API без /v1/), token_file (приватный UTF-8-файл токена, абсолютный либо относительно ~/quest). Окружение platform содержит отдельные учётные данные reader и manager. Конфигурация upstream содержит ровно upstream — базовый URL другого приложения. JSON и токены ограничены 4096 байтами. Второе приложение читает публикацию первого при собственном обновлении; восстановление первого не обновляет второй кеш. Исходный контракт содержит идентичность процессов, утверждённые адрес Vault, путь API, отпечаток reader, хеш публикации и версию без учётных данных. Для аудита consumer-audit.json содержит только request_id, path, operation и reason реальных отказов чтения; consumer/initial-observation.json — исходные путь, операцию и HTTP-статус запроса приложения. consumer-incident.json содержит ключи baseline и application с соответствующими событиями из четырёх полей. Не копируйте данные аутентификации, сырой аудит или секреты в отчёты.\n\nЕсли задание требует узкой границы reader, отрицательные проверки полномочий обращаются к secret/data/other и sys/audit: обе должны вернуть [deny]. Эта пара не доказывает запрет на всех путях Vault.\n\n# de\n\nDas Programm ist eine nur lesende HTTP-Anwendung mit Cache, kein Reparatur- oder Synchronisationswerkzeug. Es liest die Konfiguration beim Start und bei SIGHUP; HTTP-Anfragen aktualisieren sie nicht. Die PID steht in application.pid. Nach Änderungen SIGHUP an die bestehende PID senden. Prozess, Programm und Rechte nicht ersetzen oder ändern. source.json, application.pid und application.log liegen im jeweiligen Anwendungsverzeichnis. GET /status liefert immer Metadaten; GET / liefert 200 nur bei übernommener Publikation, sonst 503. Metadaten enthalten Bereitschaft, Quelle, Version und SHA-256, niemals Geheimnis oder Token. Protokolle nennen Fehlerklassen; der Status auch den HTTP-Fehlercode der Quelle. Ein fehlgeschlagenes Aktualisieren ersetzt den Cache durch Fehlerstatus. Primäradresse: http://127.0.0.1:18081; zweite Anwendung, falls vorhanden: http://127.0.0.1:18082. Vault-Konfiguration enthält genau url (Basisadresse), path (API-Pfad ohne /v1/), token_file (private UTF-8-Datei, absolut oder relativ zu ~/quest). Die Plattformumgebung stellt getrennte Reader- und Manager-Zugangsdaten bereit. Upstream-Konfiguration enthält genau upstream (Basis-URL einer Anwendung). JSON und Zugangsdaten sind auf 4096 Bytes begrenzt. Die zweite Anwendung liest die erste erst bei eigener Aktualisierung; die Reparatur der ersten aktualisiert den zweiten Cache nicht. Der ursprüngliche Vertrag enthält Prozessidentität, freigegebene Vault-Adresse, API-Pfad, Reader-Fingerabdruck, Publikationshash und Version, keine Zugangsdaten. consumer-audit.json enthält nur request_id, path, operation und reason echter abgelehnter Lesezugriffe; consumer/initial-observation.json enthält ursprünglichen Anwendungspfad, Operation und HTTP-Status. consumer-incident.json hat baseline und application mit dem jeweiligen Audit-Ereignis aus vier Feldern. Keine Authentifizierungsdaten, rohen Audit-Inhalte oder Geheimnisse in Vorfallsdateien kopieren.\n\nVerlangt eine Aufgabe die enge Reader-Grenze, prüfen die negativen Capability-Proben secret/data/other und sys/audit: beide müssen [deny] melden. Diese zwei Proben belegen keine Ablehnung aller Vault-Pfade.\n\n# es\n\nEl programa es una aplicación HTTP de solo lectura con caché, no una herramienta de reparación o sincronización. Lee la configuración al iniciar y con SIGHUP; las solicitudes HTTP no la actualizan. La PID está en application.pid. Tras cambiar la configuración, envía SIGHUP a la PID existente. No reinicies ni sustituyas el proceso, ni cambies programa o privilegios. source.json, application.pid y application.log están en cada directorio de aplicación. GET /status siempre devuelve metadatos; GET / devuelve 200 solo con una publicación adoptada, en otro caso 503. Los metadatos incluyen disponibilidad, fuente, versión y SHA-256, nunca secretos ni tokens. Los registros contienen clases de error; el estado también incluye el código HTTP de error de la fuente. Un fallo de actualización sustituye la caché por un error. Dirección primaria: http://127.0.0.1:18081; segunda aplicación, cuando exista: http://127.0.0.1:18082. La configuración Vault tiene exactamente url (dirección base), path (ruta API sin /v1/) y token_file (archivo UTF-8 privado, absoluto o relativo a ~/quest). El entorno suministra credenciales distintas de reader y manager. La configuración upstream tiene exactamente upstream (URL base de otra aplicación). JSON y credenciales se limitan a 4096 bytes. La segunda aplicación obtiene la publicación de la primera solo al actualizarse; recuperar la primera no actualiza la segunda caché. El contrato original registra identidad de procesos, dirección Vault, ruta API, huella reader, resumen y versión, sin credenciales. consumer-audit.json contiene solo request_id, path, operation y reason de lecturas denegadas reales; consumer/initial-observation.json registra ruta, operación y estado HTTP inicial de la aplicación. consumer-incident.json contiene baseline y application con el evento correspondiente de cuatro campos. No copies autenticación, auditoría sin filtrar ni secretos a los informes.\n\nCuando se exige el límite reducido de reader, las pruebas negativas de capacidades consultan secret/data/other y sys/audit: ambas deben indicar [deny]. Las dos pruebas no demuestran denegación de todas las rutas Vault.\n\n# pl\n\nProgram to aplikacja HTTP z pamięcią podręczną i dostępem tylko do odczytu, a nie narzędzie naprawy lub synchronizacji. Czyta konfigurację przy starcie oraz po SIGHUP; żądania HTTP jej nie odświeżają. PID jest w application.pid. Po zmianie konfiguracji wyślij SIGHUP do istniejącego PID. Nie restartuj ani nie zastępuj procesu, nie zmieniaj programu lub uprawnień. source.json, application.pid i application.log są w katalogu danej aplikacji. GET /status zawsze zwraca metadane; GET / zwraca 200 tylko z przyjętą publikacją, inaczej 503. Metadane zawierają gotowość, źródło, wersję i SHA-256, nigdy sekret lub token. Dzienniki zawierają klasy błędów, status także kod HTTP błędu źródła. Nieudane odświeżenie zastępuje publikację błędem. Adres główny: http://127.0.0.1:18081; drugiej aplikacji, jeśli dostarczona: http://127.0.0.1:18082. Konfiguracja Vault ma dokładnie url (adres bazowy), path (ścieżka API bez /v1/), token_file (prywatny plik UTF-8, absolutny albo względem ~/quest). Środowisko dostarcza osobne dane reader i manager. Konfiguracja upstream ma dokładnie upstream (bazowy URL innej aplikacji). JSON i dane uwierzytelniające są ograniczone do 4096 bajtów. Druga aplikacja czyta pierwszą przy własnym odświeżeniu; naprawa pierwszej nie odświeża drugiej pamięci. Pierwotny kontrakt zapisuje tożsamość procesów, zatwierdzony adres Vault, ścieżkę API, odcisk reader, skrót i wersję bez danych uwierzytelniających. consumer-audit.json zawiera tylko request_id, path, operation i reason rzeczywistych odmów odczytu; consumer/initial-observation.json zapisuje początkową ścieżkę, operację i status HTTP aplikacji. consumer-incident.json zawiera baseline i application z odpowiednimi czteropolowymi zdarzeniami. Nie kopiuj uwierzytelniania, surowego audytu ani sekretów do raportów.\n\nGdy zadanie wymaga wąskiej granicy reader, negatywne testy uprawnień dotyczą secret/data/other i sys/audit: oba mają zwracać [deny]. Te dwa testy nie dowodzą odmowy na wszystkich ścieżkach Vault.'


def provision(platform, run, address, reader, manager):
    """Start readers, freeze their original identities, and publish metadata only."""
    platform.put(run, "provided-vault-consumer.py", APPLICATION)
    platform.r.exec(run, "mkdir -p ~/quest/consumer")
    platform.put(run, "consumer/README.md", MANUAL)
    platform.r.exec(run, "mkdir -p ~/quest/consumer ~/quest/downstream")
    roles = ["consumer"] + (["downstream"] if run["level"] == 93 else [])
    platform.put(run, "consumer/source.token", reader if run["level"] == 73 else manager)
    platform.put(run, "consumer/source.json", json.dumps({
        "url": address,
        "path": "secret/dispatch" if run["level"] == 73 else "secret/data/dispatch",
        "token_file": "consumer/source.token",
    }))
    if "downstream" in roles:
        platform.put(run, "downstream/source.json", json.dumps({
            "upstream": "http://127.0.0.1:18081/retired",
        }))
    for role, mode, port in [("consumer", "vault", 18081)] + (
        [("downstream", "upstream", 18082)] if "downstream" in roles else []
    ):
        platform.r.exec(
            run,
            "cd ~/quest\numask 077\nnohup python3 -I provided-vault-consumer.py "
            + mode + " " + role + "/source.json " + str(port)
            + " > " + role + "/application.log 2>&1 &\nprintf '%s\\n' \"$!\" > "
            + role + "/application.pid\n",
        )
        platform.wait(run, "curl -fsS --max-time 1 http://127.0.0.1:" + str(port) + "/status >/dev/null", seconds=15)
    result = json.loads(platform.r.exec(
        run, "cd ~/quest\npython3 -I - <<'DQ_SNAPSHOT'\nROLES="
        + repr(roles) + "\n" + SNAPSHOT + "\nDQ_SNAPSHOT\n",
    ).stdout)
    result.update({
        "vault_url": address, "path": "secret/data/dispatch",
        "reader_sha256": hashlib.sha256(reader.encode()).hexdigest(),
        "value_sha256": hashlib.sha256(b"north-secret").hexdigest(), "version": 1,
    })
    platform.put(run, "consumer-contract.json", json.dumps(result))
    if run["level"] == 73:
        raw = platform.r.docker(
            "exec", platform.name(run, "vault"), "cat", "/vault/file/station-audit.jsonl",
        ).stdout
        events = audit_metadata(raw)
        if sorted(e["path"] for e in events) != ["secret/data/dispatch", "secret/dispatch"]:
            raise RuntimeError("Expected two actual consumer denial paths")
        platform.put(run, "consumer-audit.json", json.dumps(events))
        platform.put(run, "consumer/initial-observation.json", json.dumps({
            "path": "secret/dispatch", "operation": "read", "status": 403,
        }))
