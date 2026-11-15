# Автомасштабирование и восстановление gateway

Autoscaling требует существующей scale target, пригодного знаменателя метрики и реальной входящей работы. CPU utilization связывает usage с requested CPU; отсутствие request мешает расчёту. Правильные ресурсы не создают demand. Изучайте условия HPA, ссылки на цель, метрики Pod и заданный интерфейс обработки. Наблюдайте реальные завершения вместе с числом реплик; синтетическая обработка не является production performance SLO.

На втором этапе задания 130 listener Gateway принимает соединения, а HTTPRoute выбирает backend Service по host и порту. Изучите `gateway.yaml`, `route.yaml` и сохранённые класс, URL и namespace контроллера в `gateway-target.json`. Проверьте Gateway Accepted и route ResolvedRefs, а в настоящих системах также parent и поколение; отдельное условие может устареть или относиться к другому parent.

NetworkPolicy выбирает целевые Pod. Peer с namespaceSelector и podSelector выбирает Pod, удовлетворяющие обоим условиям в этом namespace; отдельные peer означали бы альтернативы. Сравните точную структуру одного правила `board-ingress` из задания с `ingress-policy.yaml`, затем проверьте сохранённый URL с разрешённым Host, закрытым Host и прямой доступ клиента. У неудачного запроса может быть несколько причин, поэтому сам по себе он не доказывает причину. Одноразовый адаптер и его приватные послабления TLS не являются производственной конфигурацией.

Источники: [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/), [HTTPRoute](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/), [NetworkPolicy](https://kubernetes.io/docs/reference/kubernetes-api/networking/network-policy-v1/).

Проверьте ресурсы и состояние метрик:

```sh
cd ~/quest
kubectl get deployment board -o yaml
kubectl get hpa board -o yaml
kubectl top pods -l app=board
```

На втором этапе задания 130 отдельно проверьте маршрут и политику:

```sh
kubectl get gateway,httproute,networkpolicy -o yaml
```

В задании 113 подключение к listener Gateway и ссылки на Service backend — независимые решения контроллера. Рассматривайте запрошенного родителя в контексте сохранённого listener, контроллера и текущего поколения HTTPRoute. Accepted не означает ResolvedRefs, а условия другого родителя или старого поколения не подтверждают текущее здоровье. Сохраняйте идентичность объектов маршрутизации и определения listener Gateway, сравнивая оба условия с реальным трафиком подходящего и закрытого Host.

```sh
cd ~/quest
cat gateway-target.json attachment-contract.json
kubectl get gateway,httproute,service -o yaml
```
