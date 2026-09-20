---
name: browser-qa
description: Browser QA for frontend previews, UI behavior, responsiveness, console errors, and runtime verification using Paseo browser tools. Use after implementation or whenever a user asks to verify the running UI.
compatibility: opencode
metadata:
  audience: developers
  workflow: qa
---

# Browser QA

Use Paseo's native browser tools to verify the running application. Do not claim the UI is correct without observing the live preview.

## Workflow

1. Identify the current workspace and inspect its configured scripts/services.
2. Reuse a healthy existing preview service when available. Start the configured service only if needed. Use managed workspace-script tools for this; never create or drive a generic terminal during QA.
3. Use the workspace service proxy/public preview URL returned by Paseo. Do not assume a localhost URL from the desktop browser.
4. Reuse the workspace browser tab when practical; otherwise open a new tab.
5. Navigate to the target URL and wait for the expected page state.
6. Run `browser_snapshot` first. Treat the accessibility tree as the primary source for headings, text, controls, form state, hierarchy, and stable element refs.
7. Treat `browserId` as an opaque identifier. Copy it exactly from `browser_new_tab` or `browser_list_tabs`; never construct, trim, concatenate, or transform it.
8. If a browser tool rejects `browserId`, call `browser_list_tabs`, select the matching live tab, and retry the failed browser operation once with the exact returned id. Report repeated failure as a tooling error, not an application failure.
9. Use action tools such as `browser_click` and `browser_fill` only with refs from the latest snapshot. Refresh the snapshot after navigation or meaningful DOM changes because refs expire.
10. Use `browser_screenshot` only when visual evidence matters, including layout, spacing, colors, responsive behavior, clipping, overlap, image rendering, or anything the accessibility tree cannot establish.
11. Use `browser_resize` when responsive behavior is in scope. Check at least one desktop viewport and one narrow/mobile viewport when the request concerns responsive UI. Restore the original viewport when practical.
12. Use `browser_logs` after exercising the relevant flow. Report console errors and failed or suspicious network activity separately from visual findings.
13. Separate application findings from agent/tooling failures. A failed tool invocation, invalid `browserId`, or unavailable browser host is not an application console/network failure.
14. If generic terminal tools such as `create_terminal` or `send_terminal_keys` are available in a QA session, do not use them. Report that the QA provider is misconfigured because those tools can bypass source-edit restrictions.
15. For read-only QA, when shell permission allows it, run `git status --porcelain` at the end and report whether the working tree stayed clean. Do not use shell for source modification.
16. If a test changes application state, describe the state change and avoid destructive or irreversible actions unless explicitly requested.
17. Report observed evidence, not assumptions. Distinguish PASS, FAIL, and NOT TESTED.

## Report format

Keep the report concise:

- Target: page/flow tested
- Service: healthy/unhealthy and URL source
- Functional checks: PASS/FAIL with observed evidence
- Visual checks: PASS/FAIL/NOT TESTED
- Console/network: clean or concrete findings
- Responsive checks: viewports actually tested
- Tooling errors: none or concrete agent/tool-call failures
- Working tree: clean/dirty/NOT TESTED
- Remaining risks: anything not exercised

Do not modify source files while performing a review-only Browser QA task unless the user explicitly asks for fixes.
