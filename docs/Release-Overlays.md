# Overlay конфигурации и переключение выпуска

Используйте только офлайн-песочницу. База Kustomize содержит повторно используемые ресурсы; overlay меняет выбранные части и может создать ConfigMap. В задании 108 изучите `base/board.json`, `base/kustomization.yaml` и `overlays/recovery/kustomization.yaml`. Цель patch должна указывать имя настоящего Deployment. Отрендерьте overlay до применения, изучите созданную ConfigMap и переписанную ссылку в окружении, затем дождитесь двух готовых реплик. Один префикс `route-` не доказывает суффикс hash или неизменность базы; сравните выданные файлы и результат рендеринга.

Service выбирает Pod по меткам и публикует готовые endpoint. На первом этапе задания 115 выберите выпуск green и проверьте ответ. В начале второго этапа песочница добавляет общую метку и меняет селектор; масштабируйте blue до трёх, а green до одной реплики, дождитесь готовности, изучите EndpointSlice и запросите каждый IP Pod. Один запрос к Service показывает один ответ, а не точное распределение трафика 3:1. Проверка считает четыре имени готовых endpoint, но не сопоставляет их с Pod версий. Прилипание сессий, повторное использование соединений и малые выборки могут искажать трафик.

Источники: [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [EndpointSlice](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/).

В задании 108 отрендерьте и примените recovery overlay:

```sh
cd ~/quest
kubectl kustomize overlays/recovery
kubectl apply -k overlays/recovery
kubectl rollout status deployment/board --timeout=90s
```

В задании 115 изучите Service и готовые endpoint:

```sh
cd ~/quest
kubectl get service board -o yaml
kubectl get endpointslices -l kubernetes.io/service-name=board -o yaml
kubectl get pods -l app=blue -o wide
kubectl get pods -l app=green -o wide
```
