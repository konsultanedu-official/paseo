---
name: review-delivery
description: Run the independent Audit session for functional/browser QA, security scanning, code/diff review, and Draft PR delivery without editing source.
compatibility: opencode
metadata:
  audience: developers
  workflow: audit-delivery
---

# Review / Audit Delivery

Use this skill in the **Review** profile backed by **OpenCode Audit**.

This session is independent from the Dev session. It must not edit source files. It may validate, inspect, scan, commit the already-reviewed diff, push the feature branch, and create a Draft PR only after every gate passes.

## Required order

1. Confirm the current feature branch/worktree and working-tree state.
2. Read the task/issue and final diff against the requested base.
3. Run functional/browser QA when UI or runtime behavior is in scope.
4. Run security checks appropriate to the repository.
5. Perform independent code/diff review for correctness, accessibility where relevant, maintainability, and scope.
6. If any gate fails, stop before commit/push/PR and report concrete findings back to the Dev session/user.
7. If every gate passes, checkpoint the exact reviewed diff, verify a clean working tree, push the feature branch, and create a Draft PR.
8. Never merge the base branch.

## Functional QA

When browser validation is relevant:
- load and follow `browser-qa`;
- use the running preview from the Dev session, or start the configured managed workspace preview if needed;
- verify the issue acceptance criteria in the browser;
- check desktop/mobile behavior when relevant;
- capture screenshots and console/network evidence when available;
- distinguish application defects from tooling limitations.

Do not claim runtime PASS from source inspection alone.

## Security

Load and follow `security-review` where applicable.

Before the checkpoint commit, scan the working tree when needed with the allowed `gitleaks dir` command. After a checkpoint commit, `gitleaks git` may also be used.

Run `bun audit --audit-level=high` for Bun projects unless the repository specifies another package manager/audit command.

Do not expose secret values. Separate pre-existing dependency findings from regressions introduced by the feature.

## Code and diff review

Review the complete intended change against the base branch.

Check:
- correctness against the task;
- source scope and unexpected files;
- accessibility and responsive behavior when relevant;
- security-sensitive code paths;
- unnecessary complexity or overengineering;
- dependency/config/deployment changes;
- evidence consistency with QA and security results.

The Audit session is not allowed to repair source. Any source change goes back to Dev and invalidates prior QA/security/review evidence for the changed revision.

## Delivery after PASS

Only after functional QA, security, and code review all pass on the same working diff:

1. Verify the branch is not the base branch.
2. Verify the changed-file scope again.
3. Run `git diff --check`.
4. Stage only the intended reviewed changes.
5. Commit the exact reviewed diff with an appropriate conventional commit message.
6. Verify the working tree is clean.
7. Push only the feature branch to `origin`.
8. Create a **Draft PR** to the requested base.
9. Include QA, security, review evidence and known tooling limitations in the PR body.
10. Confirm the PR is still draft and the base branch was not merged.

Never amend, squash, rebase, or merge unless the user explicitly changes this workflow.

## Result contract

End with one of:

- `REVIEW_RESULT: PASS` followed by Draft PR URL and final commit SHA.
- `REVIEW_RESULT: CHANGES_REQUIRED` with concrete findings and no delivery actions.
- `REVIEW_RESULT: BLOCKED` with the exact tooling/runtime blocker.

A PASS means only the reviewed scope passed the checks actually performed.
