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
2. Reuse a healthy existing preview service when available. Start the configured service only if needed.
3. Use the workspace service proxy/public preview URL returned by Paseo. Do not assume a localhost URL from the desktop browser.
4. Reuse the workspace browser tab when practical; otherwise open a new tab.
5. Navigate to the target URL and wait for the expected page state.
6. Run `browser_snapshot` first. Treat the accessibility tree as the primary source for headings, text, controls, form state, hierarchy, and stable element refs.
7. Use action tools such as `browser_click` and `browser_fill` only with refs from the latest snapshot. Refresh the snapshot after navigation or meaningful DOM changes because refs expire.
8. Use `browser_screenshot` only when visual evidence matters, including layout, spacing, colors, responsive behavior, clipping, overlap, image rendering, or anything the accessibility tree cannot establish.
9. Use `browser_resize` when responsive behavior is in scope. Check at least one desktop viewport and one narrow/mobile viewport when the request concerns responsive UI.
10. Use `browser_logs` after exercising the relevant flow. Report console errors and failed or suspicious network activity separately from visual findings.
11. If a test changes application state, describe the state change and avoid destructive or irreversible actions unless explicitly requested.
12. Report observed evidence, not assumptions. Distinguish PASS, FAIL, and NOT TESTED.

## Report format

Keep the report concise:

- Target: page/flow tested
- Service: healthy/unhealthy and URL source
- Functional checks: PASS/FAIL with observed evidence
- Visual checks: PASS/FAIL/NOT TESTED
- Console/network: clean or concrete findings
- Responsive checks: viewports actually tested
- Remaining risks: anything not exercised

Do not modify source files while performing a review-only Browser QA task unless the user explicitly asks for fixes.
