# Идентичность и доступ workload

Используйте только одноразовую офлайн-песочницу. Security context Pod задаёт идентичность и привилегии процесса; Pod Security admission проверяет спецификацию до запуска Pod. Изучите события ReplicaSet, проверьте Deployment и исправьте выданный `board.json`: UID 1000, seccomp RuntimeDefault, запрет повышения привилегий, удалённые capabilities и корневая файловая система только для чтения — разные меры защиты. Записываемый `emptyDir` в `/tmp` даёт временное место; проверяйте `/proc/mounts` и запись, а не делайте вывод о корневом монтировании по ошибке команды.

ServiceAccount идентифицирует workload. У проецируемого токена есть аудитория и запрошенное время жизни; kubelet его обновляет. Отключите автоматическое монтирование, когда выданный манифест требует конкретную проекцию. Role задаёт операции API, а RoleBinding связывает их с субъектами в namespace. `resourceNames: [route]` ограничивает именованный `get`; он не даёт `list`. Перед изменением изучите действующие Role и RoleBinding и выданные файлы. В задании 125 привязанным должен остаться только `controller`; запрос `observer` должен быть отклонён.

Выданные CA и endpoint позволяют проверить настоящее HTTPS. Не выводите данные доступа и не передавайте их в аргументах или файлах: прочитайте проецируемый токен в переменную shell, передайте заголовок Authorization в curl через стандартный ввод и удалите переменную после проверки. HTTP 200 для route и 403 для каждой указанной запрещённой операции подтверждают только эти запросы, а не все действующие права. Не отключайте проверку TLS и не выводите токен.

Источники: [security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/), [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/), [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

В задании 109 изучите события admission и идентичность процесса:

```sh
cd ~/quest
kubectl describe rs
kubectl get deployment board -o yaml
kubectl exec deployment/board -- id -u
```

В задании 114 этот пример проверяет route токеном reader и приватным CA:

```sh
cd ~/quest
kubectl get role reader -o yaml
kubectl get deployment reader -o yaml
api=$(cat api-endpoint)
token=$(kubectl exec deployment/reader -- cat /credential/token)
printf 'header = "Authorization: Bearer %s"\n' "$token" |
  curl --config - --cacert api-ca.pem -sS "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/route" | jq .data.route
unset token
```

В задании 125 изучите отдельные Role и RoleBinding, затем используйте токен controller:

```sh
cd ~/quest
kubectl get role station-reader -o yaml
kubectl get rolebinding station-reader -o yaml
api=$(cat api-endpoint)
token=$(kubectl exec deployment/controller -- cat /credential/token)
printf 'header = "Authorization: Bearer %s"\n' "$token" |
  curl --config - --cacert api-ca.pem -sS "$api/api/v1/namespaces/$DQ_NAMESPACE/configmaps/route" | jq .data.route
unset token
```

В квесте 037 привяжите ServiceAccount reader к Role в namespace, которая разрешает только `get` именованного ConfigMap `route` в основной API group. Проверяйте от имени workload: чтение `route` должно быть разрешено, а чтение `restricted` и список Secrets — запрещены. Доступ администратора не доказывает права workload.
