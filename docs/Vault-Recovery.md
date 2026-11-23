# Восстановление Vault и KV-v2

Доступность Vault, seal, авторизация и принятые приложением данные — отдельные границы. Эти примеры предназначены только для одноразовой игровой среды. У инициализированного запечатанного сервера уже есть хранилище и ключи; повторная инициализация не является восстановлением. Сверяйте исходную идентичность кластера. Здесь используется один файловый backend; задания не доказывают HA или аварийное восстановление из снимков.

## Наблюдение до изменений
API статуса показывает инициализацию, seal и кворум. Квитанция запуска описывает действие агента, а не постоянное здоровье приложения. Механизм управления описан в справочнике среды. Файлы долей содержат синтетические данные и должны оставаться приватными. Не выводите доли, токены и секретные ответы. Для общего примера самостоятельно выберите разрешённый файл долей и доступный адрес Vault:

```bash
(
 set -euo pipefail
 umask 077
 : "${VAULT_ADDR:?select the authorized Vault address}"
 : "${RECOVERY_SHARES:?select the authorized recovery JSON file}"
 request=$(mktemp)
 trap 'rm -f "$request"' EXIT
 count=$(jq -er 'length' "$RECOVERY_SHARES")
 for ((i=0; i<count; i++)); do
  jq -n --argjson i "$i" --slurpfile shares "$RECOVERY_SHARES" '{key:$shares[0][$i]}' > "$request"
  curl -fsS --max-time 3 -X PUT -H 'Content-Type: application/json' --data-binary @"$request" "$VAULT_ADDR/v1/sys/unseal" >/dev/null
 done
 curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized,sealed,t,n,cluster_id}'
)
```

## KV API и полномочия
В API-пути KV-v2 есть компонент data внутри mount; логический путь CLI отличается. Сопоставьте фактический запрос приложения с нужным источником и проверьте эффективные полномочия reader. Право manager обновлять одну политику не даёт права чтения данных; в сценарии восстановления у manager может вовсе не быть права изменения политики. Не расширяйте полномочия ради успешного потребителя. Перед общим приватным чтением выберите нужный путь API и существующую идентичность:

```bash
(
 set -euo pipefail
 umask 077
 : "${VAULT_ADDR:?select the authorized Vault address}"
 : "${KV_API_PATH:?select the intended KV API path}"
 : "${READER_TOKEN_FILE:?select the private existing reader credential file}"
 header=$(mktemp)
 trap 'rm -f "$header"' EXIT
 printf 'X-Vault-Token: %s\n' "$(cat "$READER_TOKEN_FILE")" > "$header"
 curl -fsS --max-time 3 -H @"$header" "$VAULT_ADDR/v1/$KV_API_PATH" | jq -e '.data.metadata.version > 0' >/dev/null
 echo OK
)
```

## Построение и распространение
Рабочая заготовка синхронизации, например sync-secret.sh, не является непрерывным контроллером и может содержать только каркас. Постройте доставку через API источника и получателя. Обновление Kubernetes Secret не меняет переменные окружения уже работающего процесса. Сохраните контроллер, программу pod и ссылку на источник; после rollout проверяйте каждый активный принадлежащий ему pod.

Приложение с кешем может обновляться при старте или по сигналу. Здоровый источник не доказывает принятие данных потребителем. Сопоставляйте идентичность источника, хранение учётных данных, версию и хеш публикации на каждой границе. Потребители обновляются независимо: сначала исправьте upstream, затем обновите downstream. Сохраняйте идентичность и привилегии процессов вместо подмены приложения. Общая проверка статуса не ремонтирует и не обновляет приложение:

```bash
(
 set -euo pipefail
 : "${APPLICATION_URL:?select the existing application base URL}"
 curl -fsS --max-time 3 "$APPLICATION_URL/status" | jq '{ready,error,status,source,path,version,value_sha256}'
)
```

## Сопоставление аудита
Запросы и ответы аудита связаны через request.id. Сравните операцию и путь с первоначальным наблюдением приложения: одинаковые отказы могут иметь разные причины. Экспортируйте только request_id, path, operation и reason. Сырые данные аутентификации и секреты не должны попадать в отчёты. Зафиксируйте отказ до изменения политики, а затем отдельно проверьте разрешённый доступ, отрицательные проверки полномочий и публикацию потребителя.

API: [схема аудита](https://developer.hashicorp.com/vault/docs/audit/schema), [unseal](https://developer.hashicorp.com/vault/api-docs/system/unseal), [чтение KV-v2](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2#read-secret-version).

## Аренды, ротация и составная доставка

Истёкший токен не может продлить сам себя. Отличайте продление действующей возобновляемой аренды от выпуска замены через ограниченную роль. Проверяйте фактический TTL, возобновляемость и ограничения роли, не выводя учётные данные. Отказ отозванного токена и успешное чтение заменой доказывают разные границы: проверьте обе и принятие замены потребителями. Не помещайте учётные данные в Git или метаданные публикации.

В составной доставке здоровье контроллера не доказывает авторизацию источника и принятие данных потребителем. Отдельно проверяйте согласование источника, приватный доступ к образу, доставку секрета и ответ приложения. Задания 044, 048, 070, 099 и 100 применяют эти понятия к политикам, продлению, ротации и доставке; нужные пути и ограничения определяйте по их контрактам.


### Чтение сохранённой политики {#vault-policy-observation}

Менеджер не смог прочитать rail-reader: у токена может не быть доступа к политике, Vault может быть недоступен либо ответ API не содержит читаемой политики. Для sys/policies/acl/rail-reader используйте менеджера. Ошибка чтения может также вызвать policy_scope из-за отсутствия читаемой политики; сначала восстановите доступ.

### Один путь данных KV-v2 {#vault-policy-scope}

Сохранённая политика недоступна либо не ограничена read на secret/data/dispatch: могли остаться начальный неверный путь, лишние разрешения, шаблоны путей или неподдерживаемая структура. Выданный apply-policy.sh отправляет reader.hcl; изменение только локального файла не меняет Vault. Нужное правило: path "secret/data/dispatch" { capabilities = ["read"] }. Допустимы комментарии HCL и одинаковые блоки read; JSON требует только этот путь и read, допускает известные ограничения параметров и wrapping, но не повторяющиеся ключи.

### Входные данные проверки Vault {#vault-inputs}

Проверка политики остановилась до подробных наблюдений: platform.env, переменные токенов и адреса, временные файлы заголовков или инструменты проверки могут быть недоступны. Проверка чтения или capabilities не смогла подготовить данные либо очистить временные файлы: platform.env, переменные Vault, заголовки или файл запроса могут быть недоступны. Работайте в ~/quest и загрузите выданный platform.env без вывода токенов. Файлы заголовков создаются приватно и удаляются при выходе. До анализа ACL проверьте запись в каталог и запуск нужных инструментов.

### Проверка от имени читателя {#vault-reader-value}

Читатель не получил north-secret: политика могла остаться на secret/data/wrong, токен может быть некорректен либо ответ KV-v2 недоступен или изменён. Чтение KV-v2 использует /v1/secret/data/dispatch и значение .data.data.value. Доступ менеджера не заменяет успешный запрос с VAULT_READER_TOKEN.

### Фактические разрешения и запреты {#vault-effective-access}

Capability читателя на dispatch не равна ровно read либо не прочитана: причиной могут быть неверный путь политики, дополнительные политики токена или сбой capabilities-self. Для secret/data/wrong читатель не сообщил только deny либо ответ недоступен: причиной могут быть начальное разрешение неверного пути, широкие или дополнительные политики токена либо сбой API. Запросите /v1/sys/capabilities-self токеном читателя для dispatch, wrong, other и sys/mounts. Нужны ровно [read] для secret/data/dispatch и [deny] для остальных трёх; сбой или некорректный ответ даёт ошибки по всем путям. Шаблон пути или другая политика токена могут оставить лишний доступ даже при успешном чтении.


### Приватные права файла токена {#renewal-token-file}

station-token отсутствует, недоступен либо имеет режим не 0600: сохранение или пересоздание без приватных прав может раскрыть токен. `stat -c %a station-token`.

### Срок аренды и пределы продления {#renewal-token-lease}

Аренда station-token не соответствует TTL >90, renewable=true, max TTL 600 и нужному набору политик либо lookup завершился ошибкой: начальных 45 секунд или продления на 10 секунд недостаточно. Недоступные platform.env или данные токена, а также сбой запуска curl/jq тоже могут прервать наблюдение. Общая платформа создаёт station-token до setup квеста с правами 0600 и начальной возобновляемой арендой 45 секунд с пределом 600. issue-token.sh запрашивает 60 секунд, а renew-request.json изначально 10. Выдайте действующий токен через выданную роль, запросите достаточное продление и проверьте TTL, пока он больше 90. Список политик должен быть ровно default и rail-reader; изменение JSON само по себе не продлевает истёкший токен.

### Фактические capabilities токена {#renewal-token-access}

station-token не подтвердил ровно read на dispatch и deny на другие данные и управление mounts: причиной могут быть неверная политика, некорректный или истёкший токен, недоступные входные данные или сбой API. Недоступные platform.env или данные токена, а также сбой запуска curl/jq тоже могут прервать наблюдение. Файл запроса capabilities должен допускать запись. Запрашивайте от имени station-token secret/data/dispatch, secret/data/other и sys/mounts: нужны ровно [read], [deny] и [deny]. Успех операции менеджера не подтверждает эти права для station-token.

### Ограниченная роль издателя {#renewal-issuer-access}

Издатель не подтвердил только update на auth/token/create/rail-station с deny на правку политики и другие роли выдачи: токен менеджера или окружение могут быть неверны, избыточно привилегированны или недоступны. Недоступные platform.env или данные токена, а также сбой запуска curl/jq тоже могут прервать наблюдение. Для VAULT_MANAGER_TOKEN требуются [update] только на auth/token/create/rail-station и [deny] на sys/policies/acl/rail-reader и auth/token/create/other. Здесь используется ограниченная выдача, а не менеджер редактирования политик из 044; JSON запроса должен допускать запись, а ответ API — чтение.

### Потребитель Secret без токенов Vault {#renewal-secret-consumer}

Не подтверждена работа Deployment reader через Secret без раскрытия токенов Vault: ссылка ROUTE, текущие Pod, обновлённые данные Secret, утечка токенов в манифест или окружение либо входные данные проверки могут быть некорректны или недоступны. Последняя действующая запись ROUTE у worker должна использовать route-secret/value без непустого литерала. JSON Deployment не должен содержать строки токенов из station-token, менеджера и исходного читателя. Нужны текущие незавершённые и неудаляемые Pod, принадлежащие Deployment через управляющие ReplicaSet по UID: каждый Running, env всех обычных контейнеров без этих токенов. worker должен читать north-secret из /tmp/route. sync-secret.sh читает station-token и обновляет только данные Secret; перезапустите потребителя, поскольку существующее окружение не обновляется автоматически. Отсутствие окружения или токена, некорректный JSON API, недоступный Python или инструменты и ошибки exec также дают эту диагностику.

### Готовность после синхронизации Secret {#renewal-consumer-readiness}

Deployment reader не завершил rollout за 3 секунды: route-secret может отсутствовать либо нагрузка ещё запускается; наблюдение или данные платформы также могут быть недоступны. `kubectl describe pods; kubectl rollout status deployment/reader --timeout=10s`.


### Восстановление существующего хранилища {#sealed-existing-initialized-store}

Статус не подтвердил initialized=true: адрес может вести в пустое или заменённое хранилище либо ответ недоступен и некорректен. Выданный Vault уже был инициализирован.  `source platform.env; curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized}'`.

### Разные доли продвигают unseal {#sealed-distinct-unseal-progress}

Статус не подтвердил sealed=false: могли быть отправлены менее двух разных выданных долей, одна доля повторена либо запрос статуса завершился ошибкой.  `source platform.env; curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{sealed,progress,t}'`.

### Сохранение исходного порога {#sealed-original-recovery-threshold}

Статус не подтвердил t=2: изменённые параметры инициализации или rekey, другой endpoint либо нечитаемый ответ мешают подтвердить исходный порог восстановления.  `source platform.env; curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{t,n}'`.

### Сохранение числа долей инициализации {#sealed-original-share-count}

Статус не подтвердил n=3: другая конфигурация инициализации или rekey, неверный endpoint либо ошибка наблюдения могут отличаться от исходного общего числа долей.  `source platform.env; curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{t,n}'`.

### Исходная идентичность кластера и наблюдения {#sealed-original-cluster-identity}

Исходная идентичность кластера Vault не подтверждена: повторная инициализация или замена хранилища меняет cluster ID; отсутствующие защищённые данные, недоступный исходный endpoint или сбой запуска также мешают сравнению. Поля статуса используют адрес из platform.env; отдельное наблюдение идентичности обращается к замороженному источнику consumer-contract.json и сравнивает cluster_id с original-cluster-id. Сохраните существующее файловое хранилище и исходный кворум. Новый инициализированный сервер с таким же порогом остаётся другим кластером. `source platform.env; curl -fsS --max-time 3 "$VAULT_ADDR/v1/sys/seal-status" | jq '{cluster_id}'; cat original-cluster-id`.

### Приватные права файла восстановления {#sealed-private-share-permissions}

unseal-shares.json не сообщил режим 600 либо недоступен для наблюдения: копирование или пересоздание файла с более широкими либо исполняемыми правами раскрывает выданные доли.  `stat -c %a unseal-shares.json`.

### Форма массива файла восстановления {#sealed-share-array-shape}

unseal-shares.json не является читаемым JSON-массивом: полный ответ инициализации, одиночная доля без массива или некорректный JSON меняют выданную форму.  `jq -e 'type=="array"' unseal-shares.json`.

### Ровно две сохранённые доли {#sealed-two-retained-shares}

Массив восстановления не содержит ровно две записи либо не разбирается: копирование всех трёх долей инициализации, потеря одной или другая структура нарушают контракт выданного файла. Исходный сервер создан с тремя долями и порогом две, а этот файл содержит только две выданные доли. Локальные проверки оценивают форму файла и разные строки; они не сверяют криптографически каждую строку с материалом ключа сервера. `jq -e 'type=="array" and length==2' unseal-shares.json`.

### Доли представлены строками {#sealed-string-share-entries}

Записи восстановления не все являются JSON-строками либо массив не читается: числа, объекты или неверно обёрнутый результат инициализации не сохраняют строковое представление долей.  `jq -e 'type=="array" and all(.[];type=="string")' unseal-shares.json`.

### Две разные записи в файле восстановления {#sealed-distinct-share-file}

Две записи восстановления не различаются либо массив некорректен: дублирование одной выданной доли не даёт двух разных вкладов для unseal.  `jq -e 'type=="array" and length==2 and .[0]!=.[1]' unseal-shares.json`.

### Чтение с выданной идентичностью reader {#sealed-approved-reader-api}

Выданный reader не прочитал north-secret из secret/data/dispatch: Vault ещё sealed, окружение, токен или путь отличаются от выданного источника либо наблюдение API и JSON не удалось. Выданная политика reader уже разрешает API KV-v2 secret/data/dispatch. Отдельная идентичность manager в этом упражнении не имеет доступа к этому пути. Проверьте unseal исходного сервера и используйте выданный reader; успешное прямое чтение не обновляет кэш приложения. `source platform.env; curl -fsS --max-time 3 -H @<(printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN") "$VAULT_ADDR/v1/secret/data/dispatch" | jq -e '.data.data.value=="north-secret"'`.

### Учётные данные и кэш исходного потребителя {#sealed-original-consumer-adoption}

Исходный потребитель не подтвердил одобренную публикацию Vault с приватной идентичностью reader: файл ещё содержит выданный manager или кэш ошибки не обновлён; изменённые процесс, программа, конфигурация, хранение токена или недоступные наблюдения также могут быть причиной. Выданное приложение запускается при sealed Vault, а token_file исходно содержит manager. Оно читает конфигурацию при запуске или SIGHUP; запросы не обновляют кэш. Исправьте конфигурацию с точными полями url/path/token_file и обычный файл reader, принадлежащий UID 1000, с режимом 0600 и защищённым fingerprint; пути допустимы относительные и абсолютные. После исправления отправьте SIGHUP существующему PID, сохранив процесс, программу и привилегии. Ответ сохраняет источник и путь Vault, SHA-256 публикации, целую версию 1 и ready=true. `cat consumer/source.json consumer/README.md; curl -fsS --max-time 3 http://127.0.0.1:18081/status`.


### Причина и наблюдение (070, secret_value) {#secret-vault-to-kubernetes-publication}

Исправление политики Vault само не доставляет значение в Kubernetes; выданный sync-secret.sh должен прочитать и опубликовать route-secret/value. Первая стадия исправляет путь Application; вторая исправляет выданную политику reader и публикует Secret готовым sync-secret.sh. Верная политика сама не создаёт объект Kubernetes. Наблюдайте из ~/quest после загрузки platform.env.

```bash
kubectl get secret route-secret -o json | jq '(.data.value | @base64d)=="north-secret"'
```

### Причина и наблюдение (070, secret_capabilities) {#secret-reader-exact-path-capabilities}

Выданная политика reader обращается к неверному пути KV-v2 либо даёт лишний доступ; нужны read на secret/data/dispatch и deny на secret/data/unrelated и sys/mounts. Первая стадия исправляет путь Application; вторая исправляет выданную политику reader и публикует Secret готовым sync-secret.sh. Верная политика сама не создаёт объект Kubernetes. Наблюдайте из ~/quest после загрузки platform.env.

```bash
curl -fsS -H "X-Vault-Token: $VAULT_READER_TOKEN" -H "Content-Type: application/json" --request POST --data '{"paths":["secret/data/dispatch","secret/data/unrelated","sys/mounts"]}' "$VAULT_ADDR/v1/sys/capabilities-self"
```


### Два отказа и четыре поля экспорта {#audit-correlate-two-denied-paths}

Исходный incident либо два consumer-incident могут терять поля, добавлять лишнее или соответствовать другому отказу; сопоставьте точные четырёхполевые записи из зафиксированного экспорта для обоих путей KV. Исходный отказ относится к secret/data/dispatch; выданное приложение обращается к secret/dispatch с уже выданным reader. Исправьте узкую живую политику и путь приложения, затем обновите кэш исходного процесса. Экспорт содержит только request_id, path, operation и reason. `jq '.[] | {request_id,path,operation,reason}' /run/dq/facts/0/consumer-audit.json`.

### Узкая политика reader KV-v2 {#audit-narrow-kv-v2-reader-policy}

Выданная политика reader указывает неверный путь или даёт лишние права; нужны read на secret/data/dispatch и deny на secret/data/other и sys/audit. После редактирования файла обновите живую именованную политику. Исходный отказ относится к secret/data/dispatch; выданное приложение обращается к secret/dispatch с уже выданным reader. Исправьте узкую живую политику и путь приложения, затем обновите кэш исходного процесса. Экспорт содержит только request_id, path, operation и reason. `curl -fsS -H @<(printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN") -H "Content-Type: application/json" --request POST --data '{"paths":["secret/data/dispatch","secret/data/other","sys/audit"]}' "$VAULT_ADDR/v1/sys/capabilities-self"`.

### Принятие исправленного источника исходным процессом {#audit-original-consumer-path-and-cached-publication}

Исходное приложение запускается с неверным путём KV и кэширует ошибку; исправьте политику reader и source-профиль, затем отправьте SIGHUP тому же PID. Сохраните приватный файл reader, идентичность процесса и одобренные HTTP-метаданные; ручного чтения Vault недостаточно. Исходный отказ относится к secret/data/dispatch; выданное приложение обращается к secret/dispatch с уже выданным reader. Исправьте узкую живую политику и путь приложения, затем обновите кэш исходного процесса. Экспорт содержит только request_id, path, operation и reason. `curl -fsS --max-time 2 http://127.0.0.1:18081/status`.


### Узкое чтение одобренного источника {#vault-pod-narrow-source-read}

Выданная policy reader изначально указывает неверный data-путь, либо authenticated read не проходит; разрешите read документированного KV-v2 data-пути, сохранив запрет на other-data и audit.  `cat reader.hcl; cat consumer/README.md`.

### Явная доставка данных {#vault-pod-explicit-delivery}

Рабочий файл синхронизации не содержит реализации, поэтому Kubernetes Secret может отсутствовать или устареть; создайте явное чтение источника и доставку одобренного значения по существующей secret-ссылке. Ошибки чтения источника или Kubernetes дают тот же маркер.  `bash -n sync-secret.sh; kubectl get secret route-secret -o json | jq "{name:.metadata.name,keys:(.data|keys)}"`.

### Принятие доставленного окружения {#vault-pod-effective-secret}

Изменение Secret не обновляет окружение существующего процесса; именованный контейнер может сохранять старое значение или не запускаться. Обновите Pod через исходный контроллер, сохранив выданную secret-ссылку и программу.  `kubectl get deployment relay -o json | jq .spec.template.spec.containers[].env; kubectl get pods`.

### Исходное приложение и приватный источник {#vault-pod-original-application-agreement}

Исходное приложение может использовать выданный manager credential или старый кэш, либо изменились идентичность процесса, источник или узкие capabilities. Сохраните приватную выданную идентичность reader, обновите тот же процесс через SIGHUP и проверьте одобренные metadata; запуск, разбор и таймауты наблюдения также дают общий fallback. Config содержит ровно url/path/token_file, использует зафиксированные URL/API-путь и остаётся обычным ограниченным по размеру файлом. Credential — обычный файл mode0600 владельца uid1000, совпадающий с выданной идентичностью reader. Сохраняются PID, старт процесса, команда, principal/group/capability status и байты программы. Metadata показывают ready=true, исходный источник, digest и целую version. Отдельная capability-проверка требует dispatch read и other-data/audit deny; два отрицательных пути не доказывают запрет всех Vault-путей. Ранние source/Secret/environment и application наблюдения независимы; их ранние сбои и лимиты могут дать общий fallback. `jq . consumer/source.json; curl -fsS --max-time 2 http://127.0.0.1:18081/status; cat consumer/application.pid`.

### Развёртывание после доставки {#vault-pod-secret-blocked-rollout}

Исходный workload может блокироваться отсутствующей доставкой Secret или другой ошибкой запуска; изучите события после синхронизации источника, сохраняя Deployment.  `kubectl rollout status deployment/relay --timeout=3s; kubectl describe deployment relay`.

### Сохранение исходного workload contract {#vault-pod-retained-workload-contract}

Могли измениться UID Deployment, selector, единственная реплика или полная pod specification, либо один текущий принадлежащий Pod не Ready с одобренным эффективным значением. Сохраните image, программу, security и secret-ссылку; ошибки API, запуска и таймауты дают тот же fallback.  `kubectl get deployment relay -o json | jq "{uid:.metadata.uid,replicas:.spec.replicas,selector:.spec.selector,template:.spec.template.spec}"; kubectl get pods -o wide`.


### Запуск существующего сервиса {#original-vault-start-existing-service}

Setup останавливает уже инициализированный исходный Vault; недоступный endpoint не означает, что данные надо инициализировать. Подайте ограниченный запрос запуска из control/README.md и повторите проверку. Ошибка запроса, неверный ответ или initialized false дают этот маркер; квитанция агента сама не доказывает здоровье сервиса. `cat control/README.md vault-agent-status.json; source platform.env; curl -fsS --max-time 2 "$VAULT_ADDR/v1/sys/init" | jq .initialized`.

### Наблюдение исходной инициализации {#original-vault-observe-original-initialization}

Исходный Vault уже инициализирован. Остановленный сервис, ошибка seal-status или нечитаемый JSON тоже нарушают initialized; восстановите доступность и изучите статус до изменения данных. Повторная инициализация или замена storage может уничтожить нужные далее идентичности. `source platform.env; curl -fsS --max-time 2 "$VAULT_ADDR/v1/sys/seal-status" | jq "{initialized,sealed}"`.

### Распечатывание исходного кластера {#original-vault-unseal-original-cluster}

Запуск остановленного процесса оставляет существующий storage запечатанным. Подайте две различные выданные доли через API распечатывания, не печатая их; одной доли недостаточно. Ошибка запроса статуса или неверный ответ тоже нарушают сравнение sealed false. `source platform.env; curl -fsS --max-time 2 "$VAULT_ADDR/v1/sys/seal-status" | jq "{sealed,progress,t,n}"`.

### Сохранение идентичности кластера {#original-vault-retain-cluster-identity}

Другой Vault или заново инициализированный storage может быть доступен и распечатан, но иметь иной ID кластера. Восстановите исходный сервис и storage; сравните cluster_id с зафиксированным original-cluster-id. Отсутствие frozen input или ошибка статуса тоже нарушают сравнение. `cat /run/dq/facts/0/original-cluster-id; source platform.env; curl -fsS --max-time 2 "$VAULT_ADDR/v1/sys/seal-status" | jq .cluster_id`.

### Сохранение кворума восстановления {#original-vault-retain-recovery-quorum}

Исходная инициализация задаёт порог t равный 2 и число долей n равное 3. Повторная инициализация или другой endpoint может дать иные параметры; восстановите исходный источник и изучите ответ. Ошибка запроса или JSON тоже нарушает сравнения; эти маркеры не требуют печатать доли. `source platform.env; curl -fsS --max-time 2 "$VAULT_ADDR/v1/sys/seal-status" | jq "{t,n}"`.

### Доступ reader к источнику {#original-vault-reader-source-boundary}

Старый запрос к источнику может не пройти при остановленном или запечатанном Vault, неверном reader или пути либо значении не north-secret. Проверьте выданный reader через приватный канал заголовка; успех источника ещё не доказывает обновление кеша приложений. `source platform.env; curl -fsS --max-time 2 -H @<(printf "X-Vault-Token: %s\n" "$VAULT_READER_TOKEN") "$VAULT_ADDR/v1/secret/data/dispatch" | jq -e ".data.data.value == "north-secret"" >/dev/null`.

### Manager сохраняет запрет {#original-vault-manager-remains-denied}

Запрос с reader вместо manager или выдача manager доступа к источнику нарушает требуемый запрет. Используйте отдельный выданный manager и ожидайте HTTP 403 на пути dispatch; ошибка сети, ответ запечатанного источника или другой HTTP-код тоже не проходят. `source platform.env; curl -sS --max-time 2 -o /dev/null -w "%{http_code}\n" -H @<(printf "X-Vault-Token: %s\n" "$VAULT_MANAGER_TOKEN") "$VAULT_ADDR/v1/secret/data/dispatch"`.

### Приватный режим файла долей {#original-vault-private-share-file-mode}

unseal-shares.json может отсутствовать или получить другие права при восстановлении. Верните режим 0600, не выводя содержимое. Это условие сравнивает только режим, не структуру JSON и не требует менять исходный кворум распечатывания. `stat -c "%a %U" unseal-shares.json`.

### Цепочка кеширующих потребителей {#original-vault-cached-consumer-chain}

Доступ к Vault сам не обновляет приложения. Первое изначально использует запрещённый manager token; исправьте точный профиль источника и приватный обычный файл reader с UID 1000 и режимом 0600, затем подайте SIGHUP исходному процессу. Исправьте устаревший URL downstream и подайте SIGHUP его исходному процессу после готовности первого. Сравните статус, логи и зафиксированные digest/version; изменения процессов, программы, прав, неверные входы и сбои наблюдения или timeout без имени дают тот же fallback. `cat consumer/source.json downstream/source.json consumer/application.log downstream/application.log; curl -fsS --max-time 2 http://127.0.0.1:18081/status; curl -fsS --max-time 2 http://127.0.0.1:18082/status`.

### Ранний ввод платформы {#original-vault-early-platform-input}

Условие упало до именованного наблюдения Vault, например из-за отсутствующего, нечитаемого или некорректного platform.env. Верните выданное окружение и текущий workspace; обычные ошибки HTTP, статуса или значения уже именованы. Обёртка выдаёт fallback только без существующего маркера и оставляет очистку приватных заголовков в исходном дочернем процессе. `test -r platform.env; bash -n platform.env; pwd`.


### Ссылка на публикацию Secret {#credential-incident-secret-publication-reference}

Выпуск токена сам не публикует значение Vault в Kubernetes. Используйте новый station-token с выданным sync-script и сохраните эффективный последний ROUTE_SECRET связанным с route-secret/value без встроенного значения. Декодированный Secret должен содержать требуемую строку north-secret. Отсутствие входов, неверная структура worker/env, ошибки API, JSON и decode дают fallback.

```bash
kubectl get deployment board -o json | jq ".spec.template.spec.containers[] | select(.name=="worker") | .env"; kubectl get secret route-secret -o json | jq -er .data.value | base64 -d | grep -qx north-secret
```

### Приватный ограниченный новый токен {#credential-incident-private-bounded-replacement}

station-token изначально отсутствует; повторное использование скомпрометированного reader или режим не 0600 нарушают восстановление. Выпустите токен через синхронный manager role с документированными параметрами, приватно сохраните ответ без печати и используйте новый отличный токен. Проверяются доступ к источнику, точные policies [default, rail-reader] и оставшийся TTL больше 0, не более 600 секунд; ошибки lookup/read/API тоже нарушают условие.

```bash
stat -c %a station-token; cat control/README.md; source platform.env; curl -fsS --max-time 2 -H @<(printf "X-Vault-Token: %s\n" "$(cat station-token)") "$VAULT_ADDR/v1/auth/token/lookup-self" | jq "{policies:.data.policies,ttl:.data.ttl}"
```

### Отзыв скомпрометированного accessor {#credential-incident-compromised-accessor-revocation}

Новый токен не отзывает исходный скомпрометированный reader. Вызовите синхронный manager revoke-accessor с зафиксированным compromised-accessor; старый выданный credential затем должен получить HTTP 403 на источнике. Ошибка сети или другой код не доказывает требуемый запрет, а статичный issuer-status не подтверждает отзыв.

```bash
source platform.env; curl -sS --max-time 2 -o /dev/null -w "%{http_code}\n" -H @<(printf "X-Vault-Token: %s\n" "$VAULT_READER_TOKEN") "$VAULT_ADDR/v1/secret/data/dispatch"
```

### Опубликованный Secret маршрута {#q100-published-route-secret}

Secret Kubernetes мог отсутствовать или сохранять прежнее значение. Когда чтение через reader заработает, выполните выданную синхронизацию и проверьте route-secret/value без вывода содержимого.

```bash
test "$(kubectl get secret route-secret -o json | jq -er .data.value | base64 -d)" = north-secret
```

### Доступ reader к dispatch {#q100-reader-dispatch}

У выданного reader могло не быть доступа к secret/data/dispatch либо источник вернул другое значение. Проверьте политику и ожидаемое поле без вывода токена или содержимого.

```bash
source platform.env; curl -fsS --max-time 3 -H @<(printf "X-Vault-Token: %s\n" "$VAULT_READER_TOKEN") "$VAULT_ADDR/v1/secret/data/dispatch" | jq -e '.data.data.value == "north-secret"' >/dev/null
```

### Отказ на соседнем пути {#q100-reader-sibling-denial}

Слишком широкая политика reader может дать доступ к secret/data/other. Проверьте, что этот запрос получает HTTP 403, и отличайте отказ от тайм-аута или другого статуса.

```bash
source platform.env; curl -sS --max-time 3 -o /dev/null -w "%{http_code}\n" -H @<(printf "X-Vault-Token: %s\n" "$VAULT_READER_TOKEN") "$VAULT_ADDR/v1/secret/data/other"
```

### Входы проверки Secret {#q100-secret-probe-input}

Проверка Secret может остановиться до сравнения значения, если недоступны выданное окружение или рабочая папка. Проверьте входы и доступ к route-secret без записи значений в логи.

```bash
pwd; test -r platform.env; kubectl get secret route-secret -o name
```

### Входы проверки reader {#q100-reader-probe-input}

Проверка reader может остановиться до HTTP-запросов, если не читается platform.env или нельзя подготовить закрытый заголовок. Проверьте входы и инструменты без вывода токена.

```bash
pwd; test -r platform.env; command -v curl
```
