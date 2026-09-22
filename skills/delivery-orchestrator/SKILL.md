---
name: delivery-orchestrator
description: Coordinate a gated Paseo delivery pipeline from one parent agent by spawning fresh Plan, Build, QA, Security, Review, checkpoint, and Delivery agents in the correct workspace.
compatibility: opencode
metadata:
  audience: developers
  workflow: orchestration
---

# Delivery Orchestrator

Use this skill when the user wants a full software-delivery pipeline without manually creating a new agent for every phase.

The parent Orchestrator is a coordinator only. It must not edit source, run implementation commands, approve its own permission requests, merge `main`, or substitute its own judgment for an independent worker gate.

## Core model

- One Paseo agent session is provider-bound.
- Keep the parent Orchestrator session alive.
- Every role transition is a fresh Paseo child agent created by the Orchestrator.
- Workers share the intended workspace/worktree through `workspaceId`.
- Use Agent profiles as launch settings. Call `list_profiles` first and materialize the chosen profile into `create_agent`; there is no profile parameter on `create_agent`.
- Do not ask the human to click **New Agent** between normal phases.

Expected worker profiles:
- `Plan`
- `Build`
- `QA`
- `Security`
- `Review`

The Delivery and checkpoint phases reuse the `Build` profile with narrowly scoped prompts.

If a required named profile is missing, do not silently weaken boundaries. Use `list_providers`, `list_models`, and `inspect_provider` only to diagnose the missing mapping, then ask the user to repair the profile unless an exact equivalent can be established.

## Profile materialization

For every worker:

1. Call `list_profiles`.
2. Select the required named profile and read its notes.
3. Build `create_agent.provider` as `<profile.provider>/<profile.model>`.
4. Copy optional `modeId` to `settings.modeId`.
5. Copy optional `thinkingOptionId` to `settings.thinkingOptionId`.
6. Copy optional `featureValues` to `settings.features`.
7. Set `workspaceId` explicitly for worktree workers.
8. Leave `notifyOnFinish` enabled.
9. Give each worker one phase only.

### Agent-scoped create_agent contract

The Orchestrator is itself an agent, so every worker launch is an **agent-scoped** `create_agent` call.

Use only these top-level fields in the worker launch payload:

- `title`
- `provider`
- `labels` when needed
- `settings`
- `initialPrompt`
- `workspaceId`
- `notifyOnFinish`

**Never pass `background` from the Orchestrator.** `background` exists only on the top-level MCP create-agent schema. Agent-scoped creation is asynchronous by default and returns immediately; `notifyOnFinish: true` is the correct way to receive completion/error/permission notifications.

Canonical worker launch shape:

```json
{
  "title": "Plan Issue #123",
  "provider": "opencode/9router/paseo-plan",
  "settings": {
    "modeId": "plan"
  },
  "initialPrompt": "Plan phase only ...",
  "workspaceId": "wks_...",
  "notifyOnFinish": true
}
```

Omit absent optional settings instead of inventing defaults. Do not add undocumented keys.

If any Paseo tool returns a schema/validation error such as `unrecognized_keys`, `invalid_type`, or `too_small`:

1. Stop retrying the same payload.
2. Read the returned validation error.
3. Remove or correct the invalid field.
4. Retry at most once with the corrected payload.
5. If the corrected call still fails, report the tooling blocker instead of looping.

Never hot-swap the parent's provider to imitate another role.

## Default gated pipeline

### 1. Plan

Launch a fresh `Plan` worker in the source workspace.

Prompt it to:
- read the requested GitHub issue/task and current repository state;
- remain read-only;
- produce a minimal implementation plan;
- identify expected changed files;
- identify acceptance checks;
- recommend an exact feature branch;
- end with `PLAN_RESULT: PASS` or `PLAN_RESULT: BLOCKED`;
- include `BRANCH: <branch-name>` when PASS.

Do not create the implementation worktree until Plan passes.

### 2. Create the feature worktree

After Plan PASS, create one worktree workspace with `create_workspace`:
- `isolation: "worktree"`
- `mode: "branch-off"`
- `branchName`: the approved Plan branch
- `baseBranch: "origin/main"` unless the task explicitly names another base.

Keep the returned `workspaceId`. All implementation and gates below use this exact workspace.

### 3. Build

Launch a fresh `Build` worker in the feature workspace.

Prompt it to:
- implement only the approved Plan and issue scope;
- run the repository's configured lint/build/focused checks;
- run `git diff --check`;
- start the managed preview when UI QA is required;
- report changed files, git status, command evidence, and preview URL;
- do not push, open a PR, merge, or run independent gates;
- leave the implementation uncommitted unless the task explicitly requires otherwise;
- end with `BUILD_RESULT: PASS` or `BUILD_RESULT: FAIL`.

If Build fails, stop the pipeline and report the blocker unless a retry is clearly safe.

### 4. QA

Launch a fresh `QA` worker in the same feature workspace.

Prompt it to:
- load and follow the `browser-qa` skill when browser/UI validation is in scope;
- verify the task's acceptance criteria against the running preview;
- remain read-only toward source;
- separate application defects from tooling limitations;
- finish with one of:
  - `QA_RESULT: PASS`
  - `QA_RESULT: PASS_WITH_LIMITATIONS`
  - `QA_RESULT: FAIL`.

A documented tooling limitation may continue only when the worker explicitly says it is not an observed application defect.

On QA FAIL:
1. Send the concrete findings back to the existing Build worker with `send_agent_prompt`.
2. Have Build fix and rerun Build validation.
3. Launch a brand-new QA worker.
4. Do not reuse the failed QA session as the independent rerun.

### 5. Checkpoint commit

After QA passes, launch a fresh `Build` worker in the same feature workspace with a checkpoint-only prompt.

It must:
- make no source changes;
- verify the expected changed-file scope;
- run `git diff --check`;
- commit the exact QA-tested diff with an appropriate conventional commit message;
- verify a clean working tree;
- not push or open a PR;
- report the actual HEAD SHA;
- end with `CHECKPOINT_RESULT: PASS` or `CHECKPOINT_RESULT: FAIL`.

Use the reported actual HEAD as the immutable revision for subsequent gates. Do not rely on a manually retyped SHA.

### 6. Security

Launch a fresh `Security` worker in the feature workspace.

Prompt it to:
- load and follow `security-review`;
- review the committed diff against the base;
- run only scanner commands allowed by its provider policy;
- keep source and git state unchanged;
- distinguish feature regressions from pre-existing dependency findings;
- end with `SECURITY_RESULT: PASS` or `SECURITY_RESULT: FAIL`.

On Security FAIL that requires source changes:
1. Send findings to the Build worker.
2. After any source change, invalidate the previous QA/checkpoint/security evidence.
3. Rerun Build validation, fresh QA, checkpoint commit, and Security before continuing.

### 7. Independent Review

Launch a fresh `Review` worker in the feature workspace.

Prompt it to:
- remain read-only;
- review the final committed diff against the base;
- check correctness, accessibility where relevant, maintainability, unnecessary complexity, and scope;
- reconcile the final diff with Build/QA/Security evidence;
- end with `REVIEW_RESULT: PASS` or `REVIEW_RESULT: CHANGES_REQUIRED`.

On CHANGES_REQUIRED, return findings to Build. After any source change, rerun every invalidated downstream gate: Build validation, QA, checkpoint, Security, and Review.

### 8. Delivery

Only after Build, QA, Security, and Review all pass on the same final revision, launch a fresh `Build` worker with a Delivery-only prompt.

It must:
- verify branch and clean working tree;
- use actual local HEAD as source of truth;
- push the feature branch;
- create a **Draft PR** to the requested base;
- include gate evidence and known tooling limitations in the PR body;
- never merge, squash, rebase, or modify source;
- report remote HEAD, PR number, PR URL, and draft state;
- end with `DELIVERY_RESULT: PASS` or `DELIVERY_RESULT: FAIL`.

The pipeline ends at Draft PR. External ChatGPT/human audit and merge remain separate decisions.

## Waiting and progress

Child agents can take time. Prefer completion notifications:
- keep `notifyOnFinish` enabled;
- do not repeatedly poll `list_agents` or `get_agent_status`;
- when a completion notification arrives, inspect the result/evidence and launch the next phase;
- use `get_agent_activity` only when a worker reports ambiguous evidence or appears blocked.

If a worker needs a permission the Orchestrator cannot grant:
- inspect `list_pending_permissions`;
- surface the exact request to the human;
- never call `respond_to_permission` from the Orchestrator.

## Evidence invariants

Before advancing a gate, verify:
- the worker ran in the intended workspace;
- the phase result marker is present;
- the working tree state is consistent with the phase;
- no source changed during QA/Security/Review;
- any source change invalidates downstream evidence generated before that change.

Do not claim PASS from source inspection when runtime evidence was required.

## Final report

Return one compact pipeline summary:

```text
Plan       PASS
Build      PASS
QA         PASS | PASS_WITH_LIMITATIONS
Checkpoint PASS  <sha>
Security   PASS
Review     PASS
Delivery   PASS  <draft-pr-url>
```

Also report:
- feature workspace/branch;
- final commit SHA;
- important limitations;
- any human permission intervention that occurred;
- explicit confirmation that `main` was not merged.

Do not merge automatically.
