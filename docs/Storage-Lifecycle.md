# Хранение, идентичность и безопасная очистка

Идентичность claim, работающий процесс и байты на томе — разные свидетельства. Сохраняйте известный исходный набор данных, определяя, какая целевая ёмкость пригодна. Замена процесса сама по себе не возвращает отсутствующие файлы, а привязка claim не доказывает их содержимое. Namespaced-определения claim, монтирования Pod и фактические файлы связывают идентичность хранилища с результатом приложения без предположения о доступе к каталогу всего кластера.

Stateful discovery связывает governing headless Service, ordinal Pod и сохранённый claim. Одна готовность не доказывает нужный listener. Независимый сетевой потребитель должен разрешать ordinal в правильном namespace и публиковать текущий ответ, не монтируя исходный claim. Сопоставляйте идентичность источника, владельца потребителя, суффикс resolver и оба интерфейса; это текущие наблюдения, не история запросов.

PersistentVolume (PV) и PersistentVolumeClaim (PVC) — разные объекты. Политика возврата PV `Retain` сохраняет том для ручного восстановления после удаления claim; настройка StorageClass по умолчанию не меняет существующий PV задним числом. В задании восстановления изучите `volume-contract.json` и `original-claim-uid`, убедитесь, что старый claim удалён, и используйте UID-предусловия с выданными значениями перед удалением старой ссылки claim. Дождитесь привязки нового claim. Этот локальный учебный том не является резервной копией вне узла.

Точка восстановления охватывает все хранилища, участвующие в транзакции приложения. Две отдельно корректные копии могут объединить разные поколения, если процесс записи публикует файлы по очереди. Изучите протокол согласованного checkpoint приложения и сравните маркеры, поколения и итоги, не полагаясь на успешное завершение команд копирования. Исходный архив неизменяемого реестра остаётся отдельной проверкой целостности. При восстановлении сравните выбранный checkpoint со смонтированными файлами и ответами текущим потребителям, сохраняя идентичность PVC и нагрузок. Этот ограниченный синтетический протокол не заменяет резервное копирование работающей БД.

Finalizer обозначает обязательство очистки, а не просто флаг, мешающий удалению. Вывод из эксплуатации может затрагивать потребителей, чьи шаблоны ещё ссылаются на прежнюю конфигурацию. Существующие Pod могут сохранить спроецированные байты после удаления источника; это не обеспечивает запуск нового Pod. Проследите связи по UID, срок жизни преемника и источники в шаблонах и текущих Pod. Независимые контрольные данные должны сохраниться. Проверки текущего состояния подтверждают идентичность, доставку и отсутствие объектов, но не полный порядок прошлых команд.

Источники: [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/), [политика возврата PV](https://kubernetes.io/docs/tasks/administer-cluster/change-pv-reclaim-policy/), [finalizer](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/).

Для задания 111 изучите сохранённый источник и контракт потребителя:

```sh
cd ~/quest
cat discovery-contract.json
kubectl get statefulset,pvc,service,pods -o yaml
kubectl exec shelf-0 -c worker -- cat /etc/resolv.conf
```

В задании 124 проверьте PV:

```sh
volume=$(jq -r .volume volume-contract.json)
kubectl get pv "$volume" -o yaml
```

Для задания 128 изучите формат checkpoint и сравните оба хранилища с архивными записями. Архив может пройти проверку целостности и всё же объединять несовместимые поколения данных приложения:

```sh
cd ~/quest
cat checkpoint-contract.json
tar tf ledger.tar
tar xOf ledger.tar ledger.txt | sha256sum
tar tf checkpoint.tar
tar xOf checkpoint.tar orders.tsv
tar xOf checkpoint.tar summary.json
kubectl get deployment,pvc,pods -o yaml
kubectl exec deployment/client -- wget -qO- -T 3 http://ledger:8080/orders.tsv
kubectl exec deployment/client -- wget -qO- -T 3 http://summary:8080/summary.json
```

Для задания 129 изучите контракты вывода из эксплуатации и метаданные без вывода данных Secret. Проследите ссылки потребителей и отпечатки смонтированных данных отдельно от состояния finalizer: одной работоспособности старых Pod недостаточно.

```sh
cat cleanup-contract.json retirement-contract.json
kubectl get configmap,secret -o json | jq '.items[] | {kind,name:.metadata.name,uid:.metadata.uid,parentUID:.metadata.labels["training.devops-quests.local/parent-uid"],owners:.metadata.ownerReferences,deleting:.metadata.deletionTimestamp}'
kubectl get deployments -o json | jq '.items[] | {name:.metadata.name,uid:.metadata.uid,volumes:.spec.template.spec.volumes,mounts:[.spec.template.spec.containers[] | {name,volumeMounts}]}'
kubectl get pods -o wide
```
