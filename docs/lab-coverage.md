# Guide and Lab coverage

Each row has complete files beside `run.sh`, an executable `check.sh` with expected
observations, and `cleanup.sh`. Start from the named profile; clean up before
repeating or moving to an overlapping experiment. The short entrance and the
full reference are separate learning routes. Scripts may deliberately fail a
command and verify its exact exit/result rather than treating any error as proof.

The [machine-readable map](../labs/coverage.yaml) accounts for every fenced block
in the 29 source snapshots, including output and diagrams. A block mapping is
provenance, **not** a claim that every historical command was executed verbatim.
Paths, fixture names, cached provider/image identities and dynamic IDs are adapted
to the owned Lab. Actual execution evidence belongs in the validation report and
smoke logs. Historical outputs and diagrams are not runnable tests.

| Guide | Profile | Short example | Full experiment | Observation / boundary |
|---|---|---|---|---|
| Health checks and container restarts | kubernetes | [probes](../labs/examples/kubernetes/probes/run.sh) | [full-probes](../labs/examples/kubernetes/full-probes/run.sh) | Readiness gates traffic; liveness restarts; HTTP startup/readiness/liveness transitions. |
| Where a Pod can run | kubernetes | [placement](../labs/examples/kubernetes/placement/run.sh) | [full-placement](../labs/examples/kubernetes/full-placement/run.sh) | Pending requests, tolerations, required node selection, two-worker spread, non-preempting priority. |
| CPU, memory and resource limits | kubernetes | [resources](../labs/examples/kubernetes/resources/run.sh) | [full-resources](../labs/examples/kubernetes/full-resources/run.sh) | Requests/limits, BestEffort/Burstable, actual CPU throttling and in-place resize. |
| Finding a Pod through a Service | kubernetes | [networking](../labs/examples/kubernetes/networking/run.sh) | [full-networking](../labs/examples/kubernetes/full-networking/run.sh) | Selectors, EndpointSlices, failed selectors and HTTP to a ready backend. |
| Persistent storage | kubernetes | [storage](../labs/examples/kubernetes/storage/run.sh) | [full-storage](../labs/examples/kubernetes/full-storage/run.sh) | PVC binding and bytes retained across Pod replacement and Lab stop/resume. |
| Updating application configuration | kubernetes | [configuration](../labs/examples/kubernetes/configuration/run.sh) | [full-configuration](../labs/examples/kubernetes/full-configuration/run.sh) | Environment, directory projection, subPath, Downward API and token projection. |
| Safely maintaining a node | kubernetes | [disruption](../labs/examples/kubernetes/disruption/run.sh) | [full-disruption](../labs/examples/kubernetes/full-disruption/run.sh) | PDB blocks voluntary eviction/drain; uncordon and explicit cleanup. |
| Diagnosing a failing application | kubernetes | [troubleshooting](../labs/examples/kubernetes/troubleshooting/run.sh) | [full-troubleshooting](../labs/examples/kubernetes/full-troubleshooting/run.sh) | Exit codes, previous logs, shell-less process access, debug profiles, TCP failures, policy, copied Pods and node CRI. |
| Selecting hosts with an inventory | ansible | [inventory](../labs/examples/ansible/inventory/run.sh) | [full-inventory](../labs/examples/ansible/full-inventory/run.sh) | Inventory groups, host variables, parent groups and SSH targets. Additional cloud/VM practicum. |
| Repeating a playbook safely | ansible | [idempotency](../labs/examples/ansible/idempotency/run.sh) | [full-idempotency](../labs/examples/ansible/full-idempotency/run.sh) | First/second runs, check/diff, command creates/removes and actual changed status. |
| Variables and their precedence | ansible | [variables](../labs/examples/ansible/variables/run.sh) | [full-variables](../labs/examples/ansible/full-variables/run.sh) | Variable precedence, scopes, extra vars and deliberate invalid/undefined values. |
| Generating configuration from templates | ansible | [templates](../labs/examples/ansible/templates/run.sh) | [full-templates](../labs/examples/ansible/full-templates/run.sh) | Template rendering, filters, native types and registered results. |
| Handling failures | ansible | [failures](../labs/examples/ansible/failures/run.sh) | [full-failures](../labs/examples/ansible/full-failures/run.sh) | failed_when, changed_when, blocks/rescue and negative cases. |
| Running handlers after changes | ansible | [handlers](../labs/examples/ansible/handlers/run.sh) | [full-handlers](../labs/examples/ansible/full-handlers/run.sh) | Notification, flush and handler ordering; service state. |
| Rolling changes across hosts | ansible | [rolling](../labs/examples/ansible/rolling/run.sh) | [full-rolling](../labs/examples/ansible/full-rolling/run.sh) | serial, forks, run_once, delegation, handlers and two real SSH targets. Additional cloud/VM practicum. |
| Organizing roles and reusable tasks | ansible | [reuse](../labs/examples/ansible/reuse/run.sh) | [full-reuse](../labs/examples/ansible/full-reuse/run.sh) | Roles, import/include, loops/tags and checksum-pinned offline Galaxy collection install. |
| Protecting secrets with Ansible Vault | ansible | [vault](../labs/examples/ansible/vault/run.sh) | [full-vault](../labs/examples/ansible/full-vault/run.sh) | Encrypted local vars, vault IDs and no_log behavior; dummy secrets only. Additional cloud/VM practicum. |
| Finding the cause of a failed playbook | ansible | [diagnosis](../labs/examples/ansible/diagnosis/run.sh) | [full-diagnosis](../labs/examples/ansible/full-diagnosis/run.sh) | Recap, verbosity, task matching, undefined variables and explicit expected failures. |
| Writing your first HCL configuration | opentofu | [hcl](../labs/examples/opentofu/hcl/run.sh) | [full-hcl](../labs/examples/opentofu/full-hcl/run.sh) | Expressions, types, locals, for expressions and validation. Additional cloud/VM practicum. |
| State, drift and recovery | opentofu | [state](../labs/examples/opentofu/state/run.sh) | [full-state](../labs/examples/opentofu/full-state/run.sh) | State addresses, refreshed drift, outputs, imports and sensitive values. |
| Storing and locking state | opentofu | [locking](../labs/examples/opentofu/locking/run.sh) | [locking](../labs/examples/opentofu/locking/run.sh) | Real concurrent local state lock and bounded waiting. Additional cloud/VM practicum. |
| Creating and replacing resources | opentofu | [lifecycle](../labs/examples/opentofu/lifecycle/run.sh) | [full-lifecycle](../labs/examples/opentofu/full-lifecycle/run.sh) | Replacement, depends_on, ignore_changes, conditions, provisioners and failed plans/applies. |
| Building a reusable module | opentofu | [module](../labs/examples/opentofu/module/run.sh) | [full-module](../labs/examples/opentofu/full-module/run.sh) | Child inputs/outputs, required arguments and module boundaries. |
| Reusing a module for multiple components | opentofu | [module-fleet](../labs/examples/opentofu/module-fleet/run.sh) | [full-module-fleet](../labs/examples/opentofu/full-module-fleet/run.sh) | count/for_each instances, output collections and input validation. |
| Moving and renaming managed resources | opentofu | [addresses](../labs/examples/opentofu/addresses/run.sh) | [full-addresses](../labs/examples/opentofu/full-addresses/run.sh) | Root-to-module moves, refactors, moved chains and removed ownership. |
| Configuring a chart with values | helm | [values](../labs/examples/helm/values/run.sh) | [full-values](../labs/examples/helm/full-values/run.sh) | Merge order, typed flags, escaped keys/commas, file/JSON input and null removal. |
| Installing, upgrading and rolling back | helm | [releases](../labs/examples/helm/releases/run.sh) | [full-releases](../labs/examples/helm/full-releases/run.sh) | Real failed upgrade and rollback; PVC data side effect persists after workload rollback. |
| How Argo CD applies changes | gitops | [sync](../labs/examples/gitops/sync/run.sh) | [full-sync](../labs/examples/gitops/full-sync/run.sh) | PreSync success/failure, sync waves and dependency order. |
| Drift correction and resource deletion | gitops | [drift](../labs/examples/gitops/drift/run.sh) | [full-drift](../labs/examples/gitops/full-drift/run.sh) | Manual drift, automation without self-heal, self-heal, prune and field ownership conflict. |

## Explicit adaptations

- Source namespaces, temporary kubeconfig paths, node names and captured process
  IDs become the current Lab's namespace, context and discovered IDs.
- Kubernetes images are preloaded and digest-pinned. Three-node topology spread
  selects workers explicitly, excluding the tainted control plane from its
  eligible domains. The NetworkPolicy case contacts a separate backend Pod;
  a connection to the caller's own Pod is not used as policy evidence.
- The scratch diagnostic program is built before Lab startup. Debug containers
  run in this Lab cluster; a node-debug `/host` is the owned kind node, not the
  application host. Stop ends debug processes, including ephemeral containers.
- Ansible source snippets gain inventories/supporting tasks and assertions. The
  Galaxy example installs the same pinned collection from a checked archive
  offline. Local-only cases do not claim to test remote connections; rolling
  tests additionally use real SSH targets.
- OpenTofu uses cached local providers, not cloud resources. Cloud backend and
  provider examples, AWS inventory/secret lookup, and VM kernel/reboot procedures
  remain visible additional practicums requiring a separately approved environment.
- Helm's data migration experiment writes a version marker on a real PVC. It
  proves that workload rollback does not reverse that side effect; it does not
  simulate database transactional correctness. GitOps uses the private repository.

No source Guide or Drills file is changed by the application layer. Refreshing
source snapshots preserves `guide-lessons.yaml` and `guide-topics.yaml`; stale
source hashes require a new editorial/coverage review before release.
