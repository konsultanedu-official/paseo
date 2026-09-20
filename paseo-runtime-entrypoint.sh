#!/usr/bin/env bash
set -euo pipefail

IMAGE_HOME="/home/paseo"

: "${HOME:=$IMAGE_HOME}"
: "${XDG_CONFIG_HOME:=${HOME}/.config}"
: "${XDG_DATA_HOME:=${HOME}/.local/share}"
: "${XDG_STATE_HOME:=${HOME}/.local/state}"
: "${XDG_CACHE_HOME:=${HOME}/.cache}"
: "${NPM_CONFIG_CACHE:=${XDG_CACHE_HOME}/npm}"

export HOME
export XDG_CONFIG_HOME
export XDG_DATA_HOME
export XDG_STATE_HOME
export XDG_CACHE_HOME
export NPM_CONFIG_CACHE

repair_runtime_tree() {
  local dir="$1"

  mkdir -p "$dir"

  if [[ "$(id -u)" == "0" ]]; then
    # Repair only root-owned entries inside known runtime-writable trees.
    # Do not follow symlinks and do not touch unrelated home/workspace data.
    find "$dir" -xdev -uid 0 -exec chown -h paseo:paseo {} +
  fi

  if ! gosu paseo test -r "$dir" || ! gosu paseo test -w "$dir" || ! gosu paseo test -x "$dir"; then
    echo "[paseo-runtime] FATAL: runtime directory is not accessible to paseo: $dir" >&2
    exit 1
  fi
}

repair_runtime_tree "${XDG_CONFIG_HOME}/opencode"
repair_runtime_tree "${XDG_CACHE_HOME}/opencode"
repair_runtime_tree "${XDG_DATA_HOME}/opencode"
repair_runtime_tree "${XDG_STATE_HOME}/opencode"
repair_runtime_tree "${HOME}/.agents/skills"
repair_runtime_tree "${NPM_CONFIG_CACHE}"

# Sync image-managed global skills into the persistent Paseo home on every start.
# This keeps generic skills available across all repositories/worktrees while
# allowing the named volume at /home/paseo to remain persistent.
if [[ -d /usr/local/share/paseo-skills ]]; then
  cp -a /usr/local/share/paseo-skills/. "${HOME}/.agents/skills/"
  if [[ "$(id -u)" == "0" ]]; then
    chown -R paseo:paseo "${HOME}/.agents/skills"
  fi
fi

exec /usr/local/bin/paseo-docker-entrypoint "$@"
