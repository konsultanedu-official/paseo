# Paseo + OpenCode runtime operations

## Runtime ownership contract

The container starts as root only long enough to prepare runtime-writable directories, then the upstream Paseo entrypoint drops the daemon and agent processes to the `paseo` user (UID/GID 1000).

Persistent state remains mounted at `/home/paseo`. The custom runtime entrypoint repairs only root-owned entries inside these known writable trees:

- `/home/paseo/.config/opencode`
- `/home/paseo/.cache/opencode`
- `/home/paseo/.local/share/opencode`
- `/home/paseo/.local/state/opencode`
- `/home/paseo/.agents/skills`
- `/home/paseo/.cache/npm`

It does not recursively chown all of `/home/paseo` or `/workspace`, does not follow symlinks, and does not modify unrelated backups such as `opencode.root-backup`.

This handles both a fresh empty volume and an existing persistent volume that contains root-owned OpenCode runtime directories.

## Ripgrep

`ripgrep` is installed in the image through the Debian package manager. OpenCode prefers a system `rg` binary when one is available, so normal runtime operation should not need to download `rg` into the OpenCode cache.

After deployment, verify as the runtime user:

```bash
gosu paseo rg --version
gosu paseo opencode debug rg files --limit 2
```

Run the second command from a project or skill directory that contains files.

## Skills

OpenCode supports global skills under both:

- `~/.config/opencode/skills/*/SKILL.md`
- `~/.agents/skills/*/SKILL.md`

These locations are persisted because `/home/paseo` is a Docker volume and are shared by projects that run as the same `paseo` user.

Installing or repairing a skill does not guarantee that an already-running shared OpenCode server will immediately rescan it. OpenCode initializes skill discovery/state per running server instance. If skills were installed after the server started, or a previous scan failed because ripgrep/cache permissions were broken, validate with a newly started OpenCode server process. Restart the shared OpenCode server only during a safe maintenance window because doing so can interrupt active agent sessions. Do not restart an active service solely to refresh skills without explicit approval.

## Existing volume migration

Redeploying the image with the same `/home/paseo` volume is the intended migration path. At container startup the scoped runtime entrypoint repairs only root-owned entries in the known writable trees listed above, preserving existing skill files, configuration, credentials, caches, and other volume data.

Do not delete or recreate the volume as a permission fix. Do not reinstall all skills as a permission fix.

If a directory is still not accessible to UID/GID 1000 after the scoped repair, startup fails with a clear error rather than taking ownership of unrelated data.

## Post-deploy validation

Run these checks after the container has been recreated with the same persistent volume:

```bash
id paseo
gosu paseo sh -lc 'printf "HOME=%s\nXDG_CONFIG_HOME=%s\nXDG_CACHE_HOME=%s\n" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"'

gosu paseo test -w /home/paseo/.config/opencode
gosu paseo test -w /home/paseo/.cache/opencode
gosu paseo test -w /home/paseo/.local/share/opencode
gosu paseo test -w /home/paseo/.agents/skills

gosu paseo rg --version
```

Then validate skill discovery from at least two different project directories with a fresh OpenCode process. Finally, validate one actual `skill` tool load through a newly started OpenCode server, not only by reading `SKILL.md` directly or by checking filesystem discovery.

If active sessions exist, postpone shared-server restart until a maintenance window.


## 9Router model exposure for Paseo

Paseo/OpenCode intentionally exposes direct coding models plus only infrastructure-level fallback combos. Product-facing 9Router combos used by OpenWebUI (for example `ai-assistant`, `cheap`, `gpt`, `gemini`, `claude`, or `free-access`) are not duplicated into the Paseo model list.

Current default agent routing:

- Plan -> `9router/cx/gpt-6-astra`
- Build -> `9router/cx/gpt-5.6-sol`
- Review -> `9router/cx/gpt-5.6-sol-review`
- General -> `9router/ag/gemini-3.8-flash-high`
- Explore -> `9router/ag/gemini-3.8-flash-low`
- Plan Deep -> `9router/high-model`

The fallback combos exposed to Paseo are `high-model`, `low-model`, and `free-model`. Keep `opencode.json` synchronized with the actual combo IDs configured in 9Router; stale combo IDs can appear selectable in OpenCode but fail at request time.


## Environment-specific OpenCode profiles

The repository ships separate OpenCode profiles so the experimental homeserver and the headless VPS do not have to expose the same 9Router combinations:

- `/etc/opencode/opencode.homelab.json` — homeserver profile, including the broader experimental combo set.
- `/etc/opencode/opencode.vps.json` — VPS profile, limited to direct coding models plus `high-model`, `low-model`, and `free-model`.

`docker-compose.yml` pins the homeserver to the homelab profile. `docker-compose.vps.yml` pins the VPS to the VPS profile. The generic `opencode.json` remains packaged for backward compatibility but is not selected by either compose profile.


## Single-agent delivery orchestration

The VPS profile includes a managed **Orchestrator** entry point for multi-stage delivery. The human starts one Orchestrator agent; it keeps its own provider/session while spawning fresh child agents for provider-bound phases in the appropriate workspace.

Managed runtime pieces:

- Paseo provider alias: `opencode-orchestrator`.
- OpenCode mode: `orchestrator`.
- Agent profile: `Orchestrator` (managed id `konsultanedu-delivery-orchestrator`).
- Global skill: `delivery-orchestrator`.

The pipeline is:

```text
Orchestrator
  -> Plan agent
  -> feature worktree
  -> Build agent
  -> QA agent
  -> checkpoint Build agent
  -> Security agent
  -> Review agent
  -> Delivery Build agent
  -> Draft PR
```

Role changes are intentionally fresh Paseo agents rather than provider hot-swaps. This preserves the QA and Security provider boundaries while removing the need for the human to click **New Agent** between normal phases.

The Orchestrator itself is not an implementation agent. Its OpenCode mode denies source edits, native task delegation, external-directory access, and general shell execution. Its Paseo provider policy disables terminals, browser actions, schedules, permission responses, destructive agent/workspace management, and workspace-script control. It retains only the workspace/agent delegation and discovery surface needed to coordinate workers. Paseo currently expresses this policy as a denylist, so revalidate the Orchestrator tool surface after significant Paseo upgrades.

If a worker needs a permission that cannot be avoided, the Orchestrator may report the pending request but must not approve it itself.

The managed profile is upserted by `paseo-runtime-entrypoint.sh` without replacing unrelated user-created agent profiles. Its model follows the active OpenCode runtime profile:

- VPS: `9router/paseo-plan`
- homelab/generic: `9router/cx/gpt-6-astra`

After rebuilding/recreating Paseo, verify only the non-secret profile/provider metadata:

```bash
docker compose -f docker-compose.vps.yml exec -T paseo \
  gosu paseo node -e '
    const fs = require("fs");
    const c = JSON.parse(fs.readFileSync("/home/paseo/.paseo/config.json", "utf8"));
    const p = c.agents?.providers?.["opencode-orchestrator"];
    const a = (c.daemon?.agentProfiles ?? []).find((x) => x.id === "konsultanedu-delivery-orchestrator");
    console.log({ provider: p?.label, profile: a?.name, model: a?.model, modeId: a?.modeId });
  '
```

Expected shape:

```text
{
  provider: 'OpenCode Orchestrator',
  profile: 'Orchestrator',
  model: '9router/paseo-plan',
  modeId: 'orchestrator'
}
```

Then start a new **Orchestrator** agent and ask it to run a delivery pipeline for an issue. The normal path should not require manually creating Plan, Build, QA, Security, Review, or Delivery tabs; those appear automatically as Paseo subagents/workspace tabs.
