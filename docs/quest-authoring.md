# Quest authoring: learning from zero

These principles are the target for quest changes. A learner may be encountering the
technology for the first time. Apply the principles relevant to the change and identify
their numbers in the PR. The examples use quest 003's local OpenTofu `notice` module;
they illustrate the target and do not claim that every feature is already implemented.

## 1. Hints form a ladder

Give each hint a distinct purpose and target: (1) the idea, linked to the concept
paragraph; (2) where to look (file, block, or name), linked to a concrete example;
(3) how to verify, with a command and expected result, linked to the verification
section. Per-hint anchors are the target; make the link land on the relevant text.

- **Good:** For 003, explain module inputs and outputs; next point to `main.tf` and
  `modules/notice`; finally suggest `tofu state list` and the expected
  `module.notice.local_file.notice` address. Each links to its own relevant passage.
- **Bad:** Repeat “check the module” three times and link each hint to the same
  undifferentiated guide section.

## 2. Link only to something new

A hint link should add a useful destination beyond the previous hint. If it cannot,
put a short, relevant 3–5 line snippet inside the hint instead of a redundant link.
Do not point to an unrelated passage merely to make links distinct.

- **Good:** For 003, include a short module-call snippet when no new guide passage
  exists, showing `source` and `station`, rather than repeating the concept link.
- **Bad:** Link every 003 hint to the same module introduction without adding a
  useful example or verification explanation.

## 3. Fade scaffolding by difficulty

Basics name the exact files, identifiers and values of the result. Medium and harder
quests state the result and its constraints, anchored to what the learner can observe
(a service response, a file's content, "the existing claim"), but never the names or
values the learner is expected to discover while diagnosing (which claim to mount, which
Secret key to reference, which field to fix). Boss quests state the incident and how the
learner can tell it is fixed. In every case, every condition enforced by a check must remain
discoverable from the brief, the supplied files or the bay itself (`kubectl get`, events,
logs, a plan). Do not make a condition a guessing game.

- **Good (045, medium):** "The data comes from the existing claim that already holds it,
  mounted read-only at `/data`"; `kubectl get pvc` shows which claim that is.
- **Bad (045):** the brief or an objective names `route-data` or gives the volume object —
  that is the diagnosis handed over.

- **Good:** In Basics quest 003, name `modules/notice`, `station`, `message`, and
  the expected state address. In a hypothetical intermediate or Boss version, let
  the learner find exact names in a clearly referenced supplied file.
- **Bad:** For 003, require `module.notice.local_file.notice` without naming it in
  the brief or any file the brief points to, regardless of difficulty.

## 4. Verify yourself through the hint ladder

The brief has no self-verification block: Live objectives and Check & finish already give
free, live feedback on every checked condition. Self-verification is taught through the
hint ladder (principle 1): diagnostic commands ("where to look") go to hint 2, verification
commands with their expected result go to hint 3. Both are paid hints, so nothing that
points at the fault is handed over for free.

- **Good (045):** hint 2 compares `kubectl describe pod -l app=reader` events and
  `kubectl get pvc` with the volumes in `reader.yaml`; hint 3 confirms with
  `kubectl rollout status deployment/reader`, `cat /data/route.txt` and a failing
  `touch /data/x` on the read-only mount.
- **Bad:** A brief section that runs `kubectl get deployment reader -o json` "to see the
  required volume contract" — it points at the broken field before the learner starts.

## 5. A failed check teaches

For each failed condition, show one diagnostic, one line explaining why it commonly
happens, and a link to the exact guide paragraph for that cause. Keep the explanation
specific and actionable; it is a likely cause, not a claim to know the learner's state.

- **Good:** For 003, “The state address is missing. This can happen when the root has
  not called or applied the child module.” Link to the matching module-call paragraph.
- **Bad:** “Check failed; try again,” or one generic cause and unrelated guide link
  for every failure.

## 6. The guide matches the quest

Every quest link must land on accurate text explaining that particular step using the
same example. Check the destination and its example, not just that the URL resolves.
Review the explanation in each supported language when it changes.

- **Good:** A 003 verification link leads to an explanation of the `notice` module's
  state address and a no-change OpenTofu plan in that example.
- **Bad:** Link 003's module verification to an unrelated Kubernetes passage, or to
  an example with different names that cannot explain the observed result.

## 7. Measure, don't guess

For each quest, measure hints revealed, check failures, and the conditions that fail
most often, so authors can identify where learners need better explanations. Preserve
learner state and privacy; collect only the needed local aggregates, never secrets or
outbound telemetry. Do not claim metrics exist until their collection is implemented.

- **Good:** For 003, compare the count of third hints with failure counts for its
  missing state-address and nonzero-plan conditions, then inspect those explanations.
- **Bad:** Rewrite 003 because one anecdote suggests a problem, or record raw shell
  output and credentials to estimate which condition failed.

## Quest presentation

This is the agreed format for every quest brief and objective. It applies at all
difficulty levels until measurements (principle 7) justify fading detail (principle 3).
`tests/test_quest_presentation.py` enforces the mechanical rules; the rest is review.
Reference quests: 045 (the full v2 format: result by level, no Verify block, hints 2/3),
011 (where artifacts live), 014 (evidence the learner must find), 059 (technique kept out
of the brief), 005 (property instead of a single value).

**The rule:** the brief states exactly *what* the result must be, never *how* to reach it
or *what is broken*.

**Brief (`brief`)**, in this order:

1. One or two sentences of context: the symptom, not the cause.
2. Entry point: the directory and only the files the learner needs. Setup leftovers are
   removed in setup, not listed.
3. `**Requirements:**` — a bulleted list with exact parameters as nested bullets.
   - Every file or path says *where* it must exist: inside which container or Pod, on which
     managed host, on the workstation, or in the Docker daemon.
   - Every value an objective names appears in the requirements as the same token
     (write `north`, not "the northbound route").
   - If the whole quest reduces to one value, state the property instead of the value,
     provided only that value satisfies it (005: "every user can read it, only its owner
     can write it, it is not executable" instead of `0644`).
   - Never state what the learner must discover (a log line, a diagnostic value) or the
     technique (`moved`, `import`, `rollout restart`, a Helm key to change, a trap's
     workaround). Those belong in hints.
   - Medium and harder quests follow principle 3: no names or values that diagnosis should
     reveal; anchor the result to what the learner can observe.
   - Do not list check-only files (records such as `original-pvc-uid`) as working files;
     state the constraint in words ("the existing claim is kept: not deleted or recreated").
4. No "Verify yourself" block (principle 4): diagnostic commands go to hint 2, verification
   commands with expected results to hint 3.
5. One line at the end for check boundaries ("the check observes current state; it does not
   prove history"). Do not delete such caveats; move them here.

Do not repeat the Bay facts paragraph ("no Internet or external DNS") or keep
"Initial success criteria" / "Success criteria" lines: requirements and objectives replace
them. Text removed from a brief because it explains *how* moves to `hints.N.text` when no
hint says it yet; hint guide links stay unchanged.

**Stage brief (`stages.N.brief`):** one non-empty line with the stage goal or constraint,
without a technique and without repeating the brief.

**Objectives (`stages.N.objectives`):** one objective per independently checked condition,
each with its own check (a condition that is one thing for the learner stays one objective).
Do not split one learner condition per host, file or item: on a fleet, one objective states the
property on every managed host ("On every managed host (`app1`, `app2`, `app3`), `/srv/routes/north`,
`/srv/routes/south` and `/srv/routes/east` are directories with mode `0750`"); use separate
objectives only when hosts or items must differ in the result, and let `[DQ:...]` name the failing
host or path. An objective or requirement never states the structure of the solution ("the playbook
separates delivery and inspection tags"); state the observable result instead ("running the
inspection selection changes nothing on any host").
Write them for a person: no jsonpath, JSON, array positions, ready YAML/HCL or commands. Name
the exact names and values of the result at Basics level (medium and harder: principle 3);
never the solution or the diagnosis (082: "The fix
is applied through Helm release `board` values, not by editing the Deployment", not "uses
`port` value `8080`"). Split objectives only in the same change that migrates the brief, or
the brief loses its goal. Multi-objective `check-N.sh` scripts follow the aggregate template
enforced by `tests/test_stage_check_invariant.py`. Add `[DQ:...]` diagnostics only where an
objective name cannot say what is missing.

**Rigid checks:** when a check compares one exact representation and an equivalent correct
solution would fail, do not bend the objective text to the check; list it under
"Rigid checks" in the PR for a check fix.

## Before opening a quest PR

- Cite the relevant principle numbers and identify the learner-facing change.
- Compare every checked condition with the brief and its explicitly referenced files;
  ensure it remains discoverable at the quest's difficulty.
- Review the hint ladder, destinations or snippets, self-verification commands, and
  each failure's cause and exact guide paragraph against the same quest example.
- Follow "Quest presentation" and run `tests/test_quest_presentation.py`.
- Translate every new or changed English learner-facing text into pl, es, de, and ru;
  check meaning and technical literals, then run `scripts/validate_i18n.py`.
- Run the required repository checks and, for changed levels, the affected matrix on
  an isolated host. Capture headed screenshots with a synthetic user for UI changes.
- Check any measurements use only necessary local data and preserve accounts, progress,
  pending hints, and Labs. Obtain independent read-only review of the final diff.
