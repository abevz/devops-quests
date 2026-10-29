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

Basics name the exact files, identifiers, and verification steps. Intermediate quests
state the goal and verification while exact names are discoverable in supplied files.
Boss quests state the incident and how the learner can tell it is fixed. In every
case, every condition enforced by a check must remain discoverable in the brief or
in files the brief explicitly points to. Do not make a condition a guessing game.

- **Good:** In Basics quest 003, name `modules/notice`, `station`, `message`, and
  the expected state address. In a hypothetical intermediate or Boss version, let
  the learner find exact names in a clearly referenced supplied file.
- **Bad:** For 003, require `module.notice.local_file.notice` without naming it in
  the brief or any file the brief points to, regardless of difficulty.

## 4. Verify yourself before Check & finish

Every quest needs a “Verify yourself before Check & finish” section with 2–3 commands
or command groups that show what the check tests, including expected results. Group
related observations when necessary; cover all checked conditions without adding
hidden prerequisites. Match the amount of detail to the difficulty rule above.

- **Good:** For 003, inspect `tofu state list` for
  `module.notice.local_file.notice`; use `cat north.txt` and `tofu output -raw message`
  to see `north-ready`; then run `tofu plan -input=false -detailed-exitcode -no-color`
  and expect exit code 0. These are three groups covering the four checked conditions.
- **Bad:** Say “verify the module works” without commands, expected results, or a
  way to see the no-change plan.

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

## Before opening a quest PR

- Cite the relevant principle numbers and identify the learner-facing change.
- Compare every checked condition with the brief and its explicitly referenced files;
  ensure it remains discoverable at the quest's difficulty.
- Review the hint ladder, destinations or snippets, self-verification commands, and
  each failure's cause and exact guide paragraph against the same quest example.
- Translate every new or changed English learner-facing text into pl, es, de, and ru;
  check meaning and technical literals, then run `scripts/validate_i18n.py`.
- Run the required repository checks and, for changed levels, the affected matrix on
  an isolated host. Capture headed screenshots with a synthetic user for UI changes.
- Check any measurements use only necessary local data and preserve accounts, progress,
  pending hints, and Labs. Obtain independent read-only review of the final diff.
