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
