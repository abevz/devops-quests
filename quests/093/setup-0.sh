set -euo pipefail
cd ~/quest
mkdir -p control
cat > control/README.md <<'DQ_CONTROL_MANUAL'
# en

Station control interface reference. This manual describes the interface, not the state of a service. Paths below are relative to `~/quest` on the workstation.

Request: `vault-repair.json`. A regular UTF-8 JSON file, at most 4096 bytes, whose decoded object supports only the string property `action`. The only permitted value is `start`: start the existing service assigned to this interface. No service selector, additional fields, symbolic links or device files are accepted. The request does not reinitialize data, change credentials or unseal storage.

The agent reads the request during objective polling. No request means no operation. A valid request is idempotent and may remain in place. `vault-agent-status.json` exists initially with `status` = `idle` (no processed request); `rejected` means the request was refused; `started` means the request was processed and the assigned process was running at that time. After starting a stopped process the agent also probes readiness. This is an agent receipt, not an application health or authorization guarantee. Missing input leaves the previous receipt unchanged. A backend ownership/readiness failure is reported by the poll and does not produce a successful receipt.

# ru

Справочник интерфейса управления станцией. Здесь описан интерфейс, а не состояние сервиса. Пути ниже указаны относительно `~/quest` на workstation.

Запрос: `vault-repair.json`. Обычный файл JSON в UTF-8 размером не более 4096 байт, в декодированном объекте которого поддерживается только строковое свойство `action`. Разрешено только значение `start`: запуск существующего сервиса, закреплённого за интерфейсом. Выбор сервиса, дополнительные поля, символические ссылки и файлы устройств не принимаются. Запрос не инициализирует данные заново, не меняет учётные данные и не распечатывает хранилище.

Агент читает запрос при опросе целей. Без запроса операции нет. Корректный запрос идемпотентен и может оставаться на месте. `vault-agent-status.json` существует с начала задания: `status` = `idle` означает отсутствие обработанного запроса; `rejected` — отказ; `started` — запрос обработан, и закреплённый процесс в тот момент работал. После запуска остановленного процесса агент также проверяет готовность. Это квитанция агента, а не гарантия работоспособности приложения или доступа. При отсутствии входного файла предыдущая квитанция сохраняется. Ошибка проверки владельца или готовности передаётся через опрос без успешной квитанции.

# de

Referenz der Stationssteuerung. Dieses Handbuch beschreibt die Schnittstelle, nicht den Zustand eines Dienstes. Die folgenden Pfade sind relativ zu `~/quest` auf der Workstation.

Anfrage: `vault-repair.json`. Reguläre UTF-8-JSON-Datei mit höchstens 4096 Bytes, deren dekodiertes Objekt nur die Zeichenketteneigenschaft `action` unterstützt. Einziger erlaubter Wert: `start`, zum Starten des dieser Schnittstelle zugeordneten bestehenden Dienstes. Dienstauswahl, Zusatzfelder, symbolische Links und Gerätedateien werden nicht akzeptiert. Die Anfrage initialisiert keine Daten neu, ändert keine Zugangsdaten und entsiegelt keinen Speicher.

Der Agent liest die Anfrage bei der Zielabfrage. Ohne Anfrage erfolgt keine Operation. Eine gültige Anfrage ist idempotent und darf liegen bleiben. `vault-agent-status.json` existiert von Anfang an: `status` = `idle` bedeutet keine verarbeitete Anfrage; `rejected` bedeutet abgelehnt; `started` bedeutet, dass die Anfrage verarbeitet wurde und der zugeordnete Prozess zu diesem Zeitpunkt lief. Nach dem Start eines gestoppten Prozesses prüft der Agent auch die Bereitschaft. Dies ist eine Agentenquittung, keine Garantie für Anwendungsgesundheit oder Zugriffsrechte. Fehlende Eingaben lassen die letzte Quittung unverändert. Fehler bei Eigentums- oder Bereitschaftsprüfungen werden über die Abfrage gemeldet, ohne Erfolgsquittung.

# es

Referencia de la interfaz de control de la estación. Este manual describe la interfaz, no el estado de un servicio. Las rutas siguientes son relativas a `~/quest` en la workstation.

Solicitud: `vault-repair.json`. Archivo JSON UTF-8 regular, de hasta 4096 bytes, cuyo objeto decodificado solo admite la propiedad de cadena `action`. El único valor permitido es `start`: iniciar el servicio existente asignado a esta interfaz. No se admiten selectores de servicio, campos adicionales, enlaces simbólicos ni archivos de dispositivo. La solicitud no reinicializa datos, cambia credenciales ni desella el almacenamiento.

El agente lee la solicitud durante el sondeo de objetivos. Sin solicitud no hay operación. Una solicitud válida es idempotente y puede permanecer en su sitio. `vault-agent-status.json` existe desde el principio: `status` = `idle` indica que no se ha procesado ninguna solicitud; `rejected` indica rechazo; `started` indica que la solicitud se procesó y el proceso asignado estaba en ejecución en ese momento. Tras iniciar un proceso detenido, el agente también comprueba su disponibilidad. Es un recibo del agente, no una garantía de salud de la aplicación ni de autorización. La ausencia del archivo conserva el recibo anterior. Un fallo de propiedad o disponibilidad se comunica mediante el sondeo y no genera un recibo de éxito.

# pl

Dokumentacja interfejsu sterowania stacją. Opisuje interfejs, a nie stan usługi. Poniższe ścieżki są względne wobec `~/quest` na workstation.

Żądanie: `vault-repair.json`. Zwykły plik JSON UTF-8, do 4096 bajtów, którego zdekodowany obiekt obsługuje tylko właściwość tekstową `action`. Jedyna dozwolona wartość to `start`: uruchomienie istniejącej usługi przypisanej do interfejsu. Wybór usługi, dodatkowe pola, dowiązania symboliczne i pliki urządzeń nie są akceptowane. Żądanie nie inicjalizuje danych ponownie, nie zmienia poświadczeń i nie odpieczętowuje magazynu.

Agent odczytuje żądanie podczas odpytywania celów. Brak żądania oznacza brak operacji. Poprawne żądanie jest idempotentne i może pozostać na miejscu. `vault-agent-status.json` istnieje od początku: `status` = `idle` oznacza brak przetworzonego żądania; `rejected` oznacza odrzucenie; `started` oznacza przetworzone żądanie i działający w tamtym momencie przypisany proces. Po uruchomieniu zatrzymanego procesu agent sprawdza też gotowość. To potwierdzenie agenta, nie gwarancja zdrowia aplikacji ani autoryzacji. Brak pliku wejściowego zachowuje poprzednie potwierdzenie. Błąd własności lub gotowości jest zgłaszany przez odpytywanie bez potwierdzenia sukcesu.
DQ_CONTROL_MANUAL
printf '%s\n' 'Station control interface: see ~/quest/control/README.md' > .motd
printf '%s\n' '{"status":"idle"}' > vault-agent-status.json
true
