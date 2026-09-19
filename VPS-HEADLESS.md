# Paseo headless VPS deployment

This profile is intended for a Linux VPS (including aaPanel-managed Docker) where Paseo runs headless and Paseo Desktop on Windows is the primary UI/browser host.

## Architecture

```text
Windows 11
  Paseo Desktop
    |-- E2EE relay via relay.paseo.sh:443 ------> Paseo daemon
    `-- local browser tabs / browser automation

VPS
  Docker: Paseo daemon + OpenCode + Git + gh + Bun + ripgrep
  /home/paseo   persistent runtime/config/skills/credentials
  /workspace    persistent repositories/worktrees
  outbound 443    official Paseo relay (primary control transport)
  127.0.0.1:6767 daemon control plane (local health/debug + SSH fallback only)
  127.0.0.1:18080 service proxy (published only through aaPanel/Nginx + Cloudflare)
```

The Web UI is disabled in `docker-compose.vps.yml`. Browser tabs are not run in the VPS container; Paseo Desktop hosts browser tabs and the daemon routes browser-tool calls to a connected Desktop browser host.

## aaPanel / Docker deployment

Use:

```bash
docker compose -f docker-compose.vps.yml up -d --build
```

Required environment variables:

```env
PASEO_PASSWORD=...
NINEROUTER_BASE_URL=...
NINEROUTER_API_KEY=...
```

Copy `.env.example` to `.env`, replace the placeholders, and keep `.env` root-readable only. The repository ignores `.env`.

The VPS preview namespace is `konsultanedu.my.id`:

```env
PASEO_SERVICE_PROXY_PUBLIC_BASE_URL=https://konsultanedu.my.id
PASEO_HOSTNAMES=localhost,127.0.0.1,.konsultanedu.my.id
PASEO_TRUSTED_PROXIES=loopback,172.16.0.0/12
__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=.konsultanedu.my.id
```

Paseo combines the script/branch/project identity into one leftmost DNS label, so a service URL stays compatible with a normal single-level wildcard certificate, for example:

```text
https://dev--konsultanedu-web-lab-dda11d6a.konsultanedu.my.id
```

For Cloudflare, create a proxied wildcard DNS record for `*.konsultanedu.my.id` pointing to the VPS. Specific DNS records continue to take precedence over the wildcard. Keep the Paseo daemon control port private; only the preview reverse proxy should be internet-facing.

For aaPanel/Nginx, use a wildcard server name and preserve the original Host header so Paseo can select the correct workspace service:

```nginx
server {
    listen 80;
    server_name *.konsultanedu.my.id;

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Terminate HTTPS at Cloudflare/aaPanel with a certificate that covers `*.konsultanedu.my.id`. Prefer Cloudflare Full (strict) with a valid origin certificate rather than exposing the Paseo service proxy directly.

Do not publish TCP 6767 on `0.0.0.0`. The compose profile binds it only to VPS loopback. Desktop should normally connect through Paseo's end-to-end encrypted relay; loopback 6767 remains available for local health/debug and SSH fallback. Keep `PASEO_PASSWORD` enabled as defense in depth for direct/loopback access.

## Windows 11 -> VPS through Paseo Desktop

Primary transport is Paseo Relay. The VPS daemon connects outbound to the official relay on TCP 443, and Paseo Desktop meets it there using Paseo's end-to-end encrypted pairing flow. No public daemon port, reverse proxy, or VPS public-IP connection is required.

After the daemon is running, enable relay and generate a pairing offer:

```bash
docker compose -f docker-compose.vps.yml exec paseo gosu paseo paseo daemon pair --relay
```

Use the resulting pairing offer/QR in Paseo Desktop. The relay setting and daemon identity live under persistent `/home/paseo`, so preserve the `paseo_home` volume across container recreation.

### SSH fallback

Paseo Desktop also supports a native Remote SSH host. Keep this as an administrative/recovery path. The SSH transport uses non-interactive OpenSSH (`BatchMode=yes`), so configure key-based login first.

From Windows PowerShell:

```powershell
ssh-keygen -t ed25519
ssh user@vps.example.com
```

Install the generated public key into the VPS user's `~/.ssh/authorized_keys` and verify that `ssh user@vps.example.com` works without an interactive password prompt.

Then in Paseo Desktop:

```text
Settings -> Add host -> Remote SSH
ssh://user@vps.example.com
```

For a non-default SSH port:

```text
ssh://user@vps.example.com:2222
```

Paseo Desktop tunnels to the already-running remote daemon at VPS `127.0.0.1:6767`. SSH transport does not install or start the daemon.

## Browser tools with a headless VPS

Paseo browser automation is Desktop-hosted. To use it, enable browser tools in the daemon config stored in the persistent `/home/paseo` volume:

```json
{
  "daemon": {
    "browserTools": {
      "enabled": true
    }
  }
}
```

The provider/profile must also have Paseo tools enabled. When Desktop is connected, browser calls are routed from the VPS daemon to the Desktop browser host. If Desktop is offline, coding agents can continue to run but Desktop-hosted browser automation is unavailable.

This is preferred over running Chromium/Playwright in the VPS when the goal is to minimize VPS CPU/RAM usage.

## External MCP servers for OpenCode/Paseo agents

There are two separate concepts:

1. **Native Paseo tools** — workspace, agent, script, worktree, and Desktop-hosted browser tools exposed by Paseo to compatible agents.
2. **External MCP servers** — GitHub, Context7, databases, Sentry, remote browser services, internal tools, etc. configured for OpenCode.

OpenCode supports local MCP processes and remote MCP servers. Example shapes:

```jsonc
{
  "mcp": {
    "local-tool": {
      "type": "local",
      "command": ["npx", "-y", "some-mcp-server"],
      "enabled": true
    },
    "remote-tool": {
      "type": "remote",
      "url": "https://mcp.example.com",
      "enabled": true
    }
  }
}
```

Use project/agent-specific MCP where possible. Paseo isolates OpenCode agents that need custom environment variables or user-injected MCP servers by giving them a dedicated OpenCode server process. Do not install a heavy browser MCP on the VPS merely to duplicate Paseo Desktop browser tools.

## Paseo MCP endpoint vs external ChatGPT integration

Paseo itself exposes an internal Streamable HTTP MCP endpoint at `/mcp/agents`. It is used to inject Paseo's tool catalog into agents. The route accepts a per-daemon-run capability token and can also accept daemon-password bearer authentication.

Do not expose `/mcp/agents` directly to the public internet as the first ChatGPT integration. It exposes a broad orchestration catalog and is designed around Paseo's agent trust model rather than role-scoped ChatGPT access.

For ChatGPT, use a separate **Paseo Control MCP** service built on `@getpaseo/client`:

```text
ChatGPT custom MCP app
       |
       | Secure MCP Tunnel / approved remote MCP transport
       v
Paseo Control MCP
  policy / scopes / approval gates
       |
       | ws://paseo:6767/ws (private Docker network or loopback)
       v
Paseo daemon
       v
projects / workspaces / worktrees / agents / scripts / OpenCode
```

The Paseo client SDK can connect to the daemon, create agents, wait for turns, and keep the agent running after the SDK client disconnects.

### Proposed MCP tool tiers

Start read-only:

```text
paseo_status
project_list
workspace_list
workspace_get
agent_list
agent_get
agent_timeline
script_list
script_status
preview_url
git_status
git_diff
git_log
```

Then controlled write:

```text
workspace_create
worktree_create
agent_start
agent_send
script_start
script_stop
run_build
run_test
```

Keep high-risk operations behind explicit approval or outside the first MCP version:

```text
arbitrary_shell
force_push
merge_main
deploy_production
delete_workspace
delete_files
```

Role presets can map the same server to different policies, e.g. PM/Planner, QA, Software Engineer, Analyst, or Auditor.

## ChatGPT support note

ChatGPT custom MCP apps are remote MCP connections. For a private/on-prem/VPS service, OpenAI documents Secure MCP Tunnel as the supported way to connect without making the MCP server public.

Full MCP including write/modify actions is currently available for ChatGPT Business and Enterprise/Edu. Read/fetch MCP access has different plan availability. Verify current ChatGPT plan capabilities before relying on write actions.

## Preview plane

Keep the control plane and preview plane separate:

```text
Control:
Paseo Desktop -> E2EE Paseo Relay -> daemon
Fallback: Paseo Desktop -> SSH -> VPS 127.0.0.1:6767

Preview:
Browser -> HTTPS *.konsultanedu.my.id -> Cloudflare -> aaPanel/Nginx
        -> VPS 127.0.0.1:18080 -> Paseo service proxy -> dynamic dev port
```

Protect private previews with an access layer such as Cloudflare Access. Do not expose dynamic Vite/dev-server ports directly.

## Validation checklist

After first deployment:

```bash
docker compose -f docker-compose.vps.yml ps
curl -fsS http://127.0.0.1:6767/api/health

docker compose -f docker-compose.vps.yml exec paseo id paseo
docker compose -f docker-compose.vps.yml exec paseo gosu paseo opencode --version
docker compose -f docker-compose.vps.yml exec paseo gosu paseo rg --version
docker compose -f docker-compose.vps.yml exec paseo gosu paseo gh --version
docker compose -f docker-compose.vps.yml exec paseo gosu paseo bun --version
```

Then verify:

1. Paseo Desktop can pair with the VPS daemon through Paseo Relay; SSH remains an optional fallback.
2. A repository can be cloned into `/workspace`.
3. OpenCode discovers global skills.
4. A dev service gets a deterministic `https://*.konsultanedu.my.id` preview URL and proxies through `127.0.0.1:18080`.
5. Browser tools work only while a Desktop browser host is connected.
6. Recreating the container with the same volumes preserves skills, credentials, projects, and config.
