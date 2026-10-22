# Book topic coverage

The original 100 IDs remain unchanged. The curriculum adds 101–130 and implements all original planned gaps. Related topics share existing quests rather than receiving duplicate single-topic exercises. Every listed practical level has two or three original oral prompts with expandable answer points; theory-only topics are available without a cloud lab. Text, questions and illustrations from the book are not redistributed.

| Chapter | Topic | Practical levels | Interview-only groups | Scope limits |
|---|---|---|---|---|
| 1 | Container and artifact boundaries | 1, 49 | architecture-runtime | No alternate orchestrator or VM provisioning. |
| 2 | API, scheduling, kubelet, CRI and node services | 11, 117, 118 | architecture-runtime | One disposable node; no production control-plane administration. |
| 3 | Pod lifecycle, probes, controllers and scheduled work | 11, 17, 40, 72, 101, 102, 103, 104, 117 | — | Native sidecar semantics follow the pinned modern Kubernetes release. |
| 4 | Resource requests, horizontal and vertical scaling | 34, 112, 126 | vertical-scaling | Real HPA/metrics-server; VPA remains an oral design exercise. |
| 5 | Node capacity and provisioning | — | node-autoscaling | Cluster Autoscaler/Karpenter/EKS are theory only; no AWS calls or node provisioning. |
| 6 | DNS, CNI policy and Service datapath | 62, 105, 118, 119 | platform-boundaries | Private DNS clone; no global DNS, host networking or CNI migration. |
| 7 | Service exposure and HTTP entry points | 106, 107, 110, 113, 118, 119 | — | Internal bridge only; no cloud LoadBalancer, public address or DNS change. |
| 8 | State, configuration and volume contracts | 11, 14, 45, 111, 120, 124 | platform-boundaries | Real local claims/reclaim; no replicated storage or multi-node CSI failure test. |
| 9 | Credentials, identity and least privilege | 31, 37, 42, 62, 99, 109, 114, 125 | platform-boundaries | Restricted PSA, actual denied requests; no node hardening or global admission policy. |
| 10 | Release strategies and observable rollouts | 67, 102, 115, 130 | traffic-strategies | Replica ratios do not guarantee traffic percentages; Istio/shadow remain theory. |
| 11 | Git reconciliation and configuration tooling | 41, 43, 50, 61, 68, 70, 75, 80, 91, 95, 100, 108, 122, 123 | — | Private Git/registry/Argo only; no external Git push, SSO deployment or multi-cluster administration. |
| 12 | API extension, reconciliation and admission | 116, 121 | — | Small finite operator and scoped real webhook; no general privileged operator platform. |
| 13 | Availability, resilience and shared failures | 77, 102, 111, 115 | availability-design | No HA/quorum claim for a single-node kind cluster. |
| 14 | Metrics, diagnosis and observability | 94, 112, 127 | observability-signals | Real scrape and PromQL; no complete logging/tracing stack or production SLO claim. |
| 15 | Disruption, backups and recovery | 77, 124, 128 | recovery-design | Quiescent text fixture restore; no live database consistency or off-host resilience claim. |
| 16 | Evidence-driven troubleshooting | 1, 14, 34, 94, 118, 129 | interview-reasoning | No host, VM or real cluster repair. |
| 17 | Clear incident reasoning and factual explanations | — | interview-reasoning | Own prompts and bullet points; no copied stories, recording or speech grading. |
| 18 | Composite incidents and interview trade-offs | 130 | interview-reasoning | Own scenarios and questions; author anecdotes and book wording are not reproduced. |

## Implementation and version differences

- Current native sidecars use init containers with restartPolicy Always. RollingUpdate budgets do not guarantee zero user-visible downtime.
- Projected ConfigMap files update eventually; environment values require a new process, and subPath has separate update behavior.
- emptyDir survives a container restart within the same Pod, but not replacement of that Pod; hostPath is not portable shared storage.
- Recycle reclaim and PodSecurityPolicy are obsolete teaching defaults; exercises use Retain and Pod Security Admission.
- In the pinned cluster kube-proxy actually uses iptables; backend selection is not a promised round-robin sequence.
- AppProject restricts Argo access; it does not enforce ResourceQuota. One Application has one destination; ApplicationSet creates multiple Applications. Git reconciliation does not restore PV contents.
- Discovery and logging use kubectl get crds and kubectl logs; malformed book examples are not reused.
- ApplicationSet defaults to a single controller namespace. An additional watched namespace is not equivalent to a namespace-scoped cache in the pinned Argo version. The exercise keeps its real controller namespace-scoped.

Pinned images are recorded in images.lock.json; Gateway API definitions and their checksum are in vendor/. New components run only for declared dependencies. Source references and the machine-readable map are in [book-coverage.yaml](book-coverage.yaml).
