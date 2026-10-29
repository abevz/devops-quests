# Восстановление Vault и KV-v2

Это руководство только для одноразовой игровой песочницы. Vault может быть инициализирован, но запечатан: инициализация создаёт хранилище и ключи, а распечатывание открывает доступ к существующим данным. Не инициализируйте Vault повторно, не выводите доли или токены и не применяйте эти шаги к настоящему Vault. В песочнице `platform.env` задаёт адрес и отдельные токены manager и reader. Manager изменяет политику читателя; reader читает разрешённый секрет.

Только в заданиях 065 и 093 `unseal-shares.json` содержит две разные игровые доли. Сохраните файл как JSON-массив из двух строк с режимом `0600` (`chmod 600 unseal-shares.json`). Каждый запрос к `/v1/sys/unseal` передаёт одну долю в поле `key`; две разные доли выполняют порог песочницы 2 из 3. Пример использует приватные временные файлы, удаляет их при выходе и выводит только состояние печати. Запускайте его, только когда игровой Vault доступен и запечатан:

```bash
(
  set -euo pipefail
  umask 077
  cd ~/quest
  source platform.env
  request=$(mktemp)
  trap 'rm -f "$request"' EXIT
  for i in 0 1; do
    jq -n --argjson i "$i" --slurpfile shares unseal-shares.json \
      '{key:$shares[0][$i]}' > "$request"
    curl -fsS -X PUT -H 'Content-Type: application/json' \
      --data-binary @"$request" "$VAULT_ADDR/v1/sys/unseal" >/dev/null
  done
  curl -fsS "$VAULT_ADDR/v1/sys/seal-status" | jq '{initialized,sealed,t,n}'
)
```

В KV-v2 `secret` — точка монтирования, а путь чтения API — `/v1/secret/data/dispatch`; значение находится в `.data.data.value`. Токену reader нужно право `read` на `secret/data/dispatch`. Пример проверяет ожидаемое игровое значение, не выводя токен или ответ:

```bash
(
  set -euo pipefail
  umask 077
  cd ~/quest
  source platform.env
  header=$(mktemp)
  trap 'rm -f "$header"' EXIT
  printf 'X-Vault-Token: %s\n' "$VAULT_READER_TOKEN" > "$header"
  curl -fsS -H @"$header" "$VAULT_ADDR/v1/secret/data/dispatch" \
    | jq -e '.data.data.value == "north-secret"' >/dev/null
  echo OK
)
```

В задании 083 Vault уже распечатан: исправьте политику `rail-reader` токеном manager, запустите выданный `sync-secret.sh` и дождитесь развёртывания `deployment/relay`. Скрипт по запросу — адаптер песочницы, а не постоянно работающий контроллер; после изменения Secret работающему процессу может понадобиться перезапуск. Проверьте ключ Secret `value` и переменную процесса `ROUTE_SECRET`, не выводя учётные данные. В задании 093 ограниченный агент запускает существующий процесс, когда `vault-repair.json` содержит `{"action":"start"}`; дождитесь запуска перед распечатыванием. Ответ 403 для manager на пути KV означает отказ этому токену. Текущее состояние и доступ не доказывают всю историю восстановления.

В задании 083 этот пример записывает ограниченную политику reader и запускает выданную синхронизацию:

```bash
(
  set -euo pipefail
  umask 077
  cd ~/quest
  cat > reader.hcl <<'POLICY'
path "secret/data/dispatch" { capabilities = ["read"] }
POLICY
  source platform.env
  header=$(mktemp)
  payload=$(mktemp)
  trap 'rm -f "$header" "$payload"' EXIT
  printf 'X-Vault-Token: %s\n' "$VAULT_MANAGER_TOKEN" > "$header"
  jq -n --rawfile policy reader.hcl '{policy:$policy}' > "$payload"
  curl -fsS -X PUT -H @"$header" -H 'Content-Type: application/json' \
    --data-binary @"$payload" "$VAULT_ADDR/v1/sys/policies/acl/rail-reader" >/dev/null
  bash sync-secret.sh
  kubectl rollout status deployment/relay --timeout=90s
)
```

Документация API: [unseal](https://developer.hashicorp.com/vault/api-docs/system/unseal), [чтение KV-v2](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2#read-secret-version).

В квесте 044 разрешите политике reader только `read` на API-пути KV-v2 `secret/data/dispatch`; компонент `data` входит в API-путь. Примените политику от имени manager, затем проверьте reader: нужное чтение и capability `[read]` должны проходить, а `secret/data/wrong`, `secret/data/other` и `sys/mounts` — давать `[deny]`. Сохраните стандартную политику самопроверки. Не выводите токены и ответы с секретами; несколько отрицательных проверок сами по себе не доказывают отсутствие других разрешений.

В квесте 048 истекший токен не может продлить сам себя. Получите новый ограниченный reader-токен через выданный issuer, задайте запрошенное продление 180 секунд и продлите его в пределах максимума роли 600 секунд. Сохраните `station-token` с режимом `0600`, проверьте возможность продления и остаток более 90 секунд, затем выданным sync-скриптом доставьте только значение приложения в workload. Проверьте границы возможностей reader и issuer; не встраивайте и не выводите Vault-токен.

В квесте 073 экспортированные метаданные аудита описывают реальный отказ без значений секретов. Запишите только зафиксированные request ID, path, operation и reason, затем разрешите reader только чтение dispatch и проверьте разрешенные и запрещенные capabilities. Не копируйте токены или ответы с секретами в запись об инциденте.

В квесте 093 запустите только выданный существующий Vault, затем снимите seal с помощью двух игровых долей, не выводя их. Сохраните для `unseal-shares.json` режим `0600` и исходный cluster ID; проверьте initialized и unsealed, разрешенный доступ reader и запрещенное чтение manager. Не инициализируйте Vault заново и не заменяйте хранилище.

В квесте 099 замените только скомпрометированный игровой reader через ограниченный issuer. Храните новый невозобновляемый токен на 300 секунд в `station-token` с режимом `0600`, отзовите записанный старый accessor и проверьте отказ старого токена, ограниченный доступ нового и ответ доставленного board. Не помещайте токены в Git или логи.
