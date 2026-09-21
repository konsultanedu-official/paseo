# Paseo Read-Only MCP

A deliberately narrow MCP facade for auditing Paseo from external clients.

## Scope

Exposed tools are read-only:

- `paseo_status`
- `paseo_list_projects`
- `paseo_list_workspaces`
- `paseo_list_agents`
- `paseo_git_status`
- `paseo_git_log`
- `paseo_git_diff`

It intentionally does **not** expose:

- agent creation or messaging
- terminal creation or keystrokes
- file reads/writes
- workspace creation/archive
- browser actions
- schedule/heartbeat actions
- permission responses
- arbitrary shell execution
- secrets or daemon configuration

The workspace volume is mounted read-only. Git tools invoke fixed argument arrays without a shell.

## Endpoints

- `GET /healthz`
- `POST /mcp` — MCP Streamable HTTP, stateless JSON responses

The Compose deployment binds the service to VPS loopback only. Do not publish it directly to the internet.

## ChatGPT plan note

As of September 2026, ChatGPT Plus cannot attach custom MCP apps directly. Keep this service private and use it for local validation/future supported clients. ChatGPT Plus can continue using GitHub issues/PRs as the audit bridge.

If a supported ChatGPT plan/workspace is used later, connect this private MCP through OpenAI Secure MCP Tunnel rather than exposing the MCP port publicly.
