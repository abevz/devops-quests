# Восстановление нагрузок Kubernetes

Эти шаги предназначены только для одноразовой песочницы задания. Контроллер создаёт Pod из шаблона; изменения и готовность требуют времени. Сначала изучите выданные манифесты, затем дождитесь изменений и проверьте реальные Pod и ответы.

## Init-контейнеры и нативные sidecar

Обычные init-контейнеры в `initContainers` выполняются по очереди и должны завершиться до запуска обычных контейнеров приложения. Нативный sidecar — init-контейнер с `restartPolicy: Always`; он может продолжать работу рядом с приложением. Его `startupProbe` может задерживать следующий контейнер. Контейнеры обмениваются файлами через общий `emptyDir`, существующий в течение жизни Pod. Используйте `kubectl get pods` и `kubectl describe pod` для проверки состояний и событий; сравните probe, команды и тома с `board.json`. Сам по себе работающий процесс не доказывает, что приложение читает входные данные.

## Rollout и откат Deployment

Deployment управляет репликами и ревизиями шаблона Pod. `Recreate` удаляет старые Pod перед заменой; `RollingUpdate` управляет заменой через `maxUnavailable` и `maxSurge`. Перед откатом изучите `kubectl rollout history deployment/board` и выданный `healthy-revision`, затем выполните `kubectl rollout undo deployment/board --to-revision=N`, заменив N записанной ревизией. Дождитесь `kubectl rollout status deployment/board --timeout=90s`, затем проверьте готовность и ответ сервиса. Сохранение UID из `original-deployment-uid` сохраняет тот же объект Deployment. Одно только число готовых реплик не гарантирует бесперебойную работу.

## Размещение DaemonSet

DaemonSet создаёт Pod на каждом подходящем узле. `nodeSelector` ограничивает выбор; изучите `kubectl get nodes --show-labels` и выданный `relay.json`. Не меняйте метки узлов ради совпадения. Дождитесь `kubectl rollout status daemonset/relay --timeout=90s`, сравните числа desired, ready и available, проверьте владельца и узел Pod. Проверьте ответы Pod и Service. Параметры безопасности Pod в манифесте, включая non-root, seccomp и capabilities, остаются важны при правильном размещении.

Источники: [init и нативные sidecar](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/), [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/).

В квесте 101 обычный init-контейнер должен завершиться до последующей инициализации; native sidecar — перезапускаемый init-контейнер, который может продолжать работать. Исправьте путь входа `prepare`, сохраните watcher и порядок volumes, затем проверьте состояние Pod, непустой heartbeat и ответ board. Настройте `prepare` на копирование `/input/route` в `/shared/route` и сохраните startup probe watcher `test -s /shared/heartbeat`. Для probe установлены `periodSeconds: 1` и `failureThreshold: 10`; один не помеченный для удаления Pod должен иметь успешный prepare, запущенный работающий watcher и готовый обычный контейнер. Проверьте ответ `north-101` от `board:8080/route`; проверка heartbeat не доказывает, что использовался тот же Pod.

В квесте 102 используйте записанную исправную revision, чтобы откатить сломанный шаблон Pod. Стратегия Deployment — отдельное поле: задайте указанные ограничения RollingUpdate, сохраните UID и две реплики, проверьте готовность и ответ. На следующем этапе исправьте readiness probe, сохранив новое содержимое. Нулевой бюджет unavailable сам по себе не гарантирует отсутствие простоя. Используйте числовые `maxUnavailable: 0` и `maxSurge: 1`; ожидаемые ответы — `north-102`, затем `north-102-v3`. HTTP-порт readiness должен быть `8080`.

В квесте 104 приостановленный CronJob не создает новые Jobs по расписанию. Установите `suspend: false` и `concurrencyPolicy: Forbid`, сохранив расписание и остальные указанные поля. Дождитесь успешного Job, созданного контроллером, с scheduled timestamp равным последнему `lastScheduleTime`, и проверьте его логи. Ручной Job не доказывает работу расписания; с наступлением новой минуты может потребоваться снова подождать. Его логи должны содержать ровно `north-104`. Сохраните `* * * * *`, `Etc/UTC`, deadline `20` и успешный/ошибочный history limits `1`.

В квесте 040 после последовательного этапа fleet сохраните Service board и selector, разворачивая две готовые реплики с ответом `north-40`. Установите `maxUnavailable: 0` и `maxSurge: 1`. Бюджет контроллера зависит от готовности и доступной емкости; сам по себе он не доказывает отсутствие потерянных запросов.

В квесте 072 Job создаёт Pod и записывает неудачные попытки. Сохраните исходный Job и ошибочную команду, задайте `backoffLimit` 1 и `activeDeadlineSeconds` 30, оставив `parallelism` 1 и `restartPolicy` `Never`. Сравните UID Job с `/run/dq/facts/0/original-job-uid`; проверьте, что счётчик ошибок не меньше 1, есть условие `Failed` и принадлежащий Job завершившийся с ошибкой Pod с кодом выхода worker 1. Число повторов и срок ограничивают разные вещи.
