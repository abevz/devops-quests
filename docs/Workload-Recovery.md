# Восстановление нагрузок Kubernetes

Эти шаги предназначены только для одноразовой песочницы задания. Контроллер создаёт Pod из шаблона; изменения и готовность требуют времени. Сначала изучите выданные манифесты, затем дождитесь изменений и проверьте реальные Pod и ответы.

## Init-контейнеры и нативные sidecar

Обычные init-контейнеры в `initContainers` выполняются по очереди и должны завершиться до запуска обычных контейнеров приложения. Нативный sidecar — init-контейнер с `restartPolicy: Always`; он может продолжать работу рядом с приложением. Его `startupProbe` может задерживать следующий контейнер. Контейнеры обмениваются файлами через общий `emptyDir`, существующий в течение жизни Pod. Используйте `kubectl get pods` и `kubectl describe pod` для проверки состояний и событий; сравните probe, команды и тома с `board.json`. Сам по себе работающий процесс не доказывает, что приложение читает входные данные.

## Rollout и откат Deployment

Deployment управляет репликами и ревизиями шаблона Pod. `Recreate` удаляет старые Pod перед заменой; `RollingUpdate` управляет заменой через `maxUnavailable` и `maxSurge`. Перед откатом изучите `kubectl rollout history deployment/board` и выданный `healthy-revision`, затем выполните `kubectl rollout undo deployment/board --to-revision=N`, заменив N записанной ревизией. Дождитесь `kubectl rollout status deployment/board --timeout=90s`, затем проверьте готовность и ответ сервиса. Сохранение UID из `original-deployment-uid` сохраняет тот же объект Deployment. Одно только число готовых реплик не гарантирует бесперебойную работу.

## Размещение DaemonSet

DaemonSet создаёт Pod на каждом подходящем узле. `nodeSelector` ограничивает выбор; изучите `kubectl get nodes --show-labels` и выданный `relay.json`. Не меняйте метки узлов ради совпадения. Дождитесь `kubectl rollout status daemonset/relay --timeout=90s`, сравните числа desired, ready и available, проверьте владельца и узел Pod. Проверьте ответы Pod и Service. Параметры безопасности Pod в манифесте, включая non-root, seccomp и capabilities, остаются важны при правильном размещении.

Источники: [init и нативные sidecar](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/), [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/).
