---
name: security-review
description: Read-only application security review using code inspection plus deterministic scanners. Use for branch, diff, or repository security review without modifying source files.
compatibility: opencode
metadata:
  audience: developers
  workflow: security
---

# Security Review

Perform a read-only security review. Do not modify source files, configuration, lockfiles, git state, or runtime state.

## Sources of evidence

Use multiple evidence types and keep them distinct:

1. **Code/diff review**
   - Inspect the relevant git diff and changed files.
   - Look for authentication/authorization mistakes, unsafe trust boundaries, injection risks, secret handling, insecure defaults, dangerous deserialization/eval patterns, client/server boundary mistakes, and supply-chain changes.
   - Do not report generic theoretical risks without a concrete code path or configuration.

2. **Secret scanning**
   - Verify Gitleaks is available with `gitleaks version`.
   - For committed repository history, run `gitleaks git --redact --no-banner`.
   - Never disable redaction.
   - Treat scanner findings as evidence to investigate, not automatic proof of exploitable exposure.
   - Do not print or reconstruct detected secret values.

3. **Dependency audit**
   - If the repository uses Bun and has a supported lockfile, run `bun audit --audit-level=high`.
   - A non-zero exit code with reported vulnerabilities is a finding, not a tooling failure.
   - Distinguish production dependency risk from dev-only/tooling dependency risk when the evidence allows it.

4. **Git state**
   - Use `git status --porcelain` before and after the review.
   - Use `git diff` or `git diff --stat` to understand the review scope.
   - The working tree must remain unchanged by the security review.

## Rules

- Never create, edit, delete, commit, push, merge, or deploy.
- Never use generic Paseo terminal/control-plane tools during security review.
- Never use a workaround if a blocked command would be required.
- Do not read or expose .env files, credentials, private keys, tokens, or secret stores.
- Do not weaken scanner configuration just to obtain a clean result.
- Separate application findings from scanner/tooling errors.
- Prefer concrete severity based on impact and reachability; if uncertain, say so.
- If the requested scope is only a diff/branch, do not silently broaden the conclusion to the entire repository.

## Report format

- Scope reviewed
- Deterministic checks run
- Findings, highest severity first
  - Severity
  - Evidence/location
  - Impact
  - Recommended remediation
- Secret scan result
- Dependency audit result
- Tooling errors
- Working tree: clean/dirty/NOT TESTED
- Residual risk / not tested

A clean scanner result does not prove the application is secure. State what was actually checked.
