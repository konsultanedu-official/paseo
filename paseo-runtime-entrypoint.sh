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

# Keep managed restricted-provider policies reproducible without overwriting
# user-managed profiles or unrelated Paseo settings.
PASEO_CONFIG_FILE="${HOME}/.paseo/config.json"
if [[ -f "${PASEO_CONFIG_FILE}" ]]; then
  PASEO_CONFIG_FILE="${PASEO_CONFIG_FILE}" node <<'NODE'
const fs = require("fs");
const path = process.env.PASEO_CONFIG_FILE;
const raw = fs.readFileSync(path, "utf8");
const config = JSON.parse(raw);

config.agents ??= {};
config.agents.providers ??= {};
config.agents.providers["opencode-qa"] = {
  extends: "opencode",
  label: "OpenCode QA",
  description: "OpenCode with a restricted Paseo tool catalog for runtime and browser QA.",
  paseoTools: {
    enabled: true,
    disabledTools: [
      "create_agent",
      "send_agent_prompt",
      "cancel_agent",
      "archive_agent",
      "kill_agent",
      "update_agent",
      "set_agent_mode",
      "create_workspace",
      "rename_workspace",
      "archive_workspace",
      "create_terminal",
      "kill_terminal",
      "capture_terminal",
      "list_terminals",
      "send_terminal_keys",
      "create_schedule",
      "pause_schedule",
      "resume_schedule",
      "update_schedule",
      "run_schedule_once",
      "delete_schedule",
      "create_heartbeat",
      "delete_heartbeat",
      "respond_to_permission",
      "browser_evaluate",
      "browser_upload"
    ]
  }
};


config.agents.providers["opencode-security"] = {
  extends: "opencode",
  label: "OpenCode Security",
  description: "OpenCode for read-only security review with no Paseo control-plane tools.",
  paseoTools: {
    enabled: false
  }
};

fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
NODE
  if [[ "$(id -u)" == "0" ]]; then
    chown paseo:paseo "${PASEO_CONFIG_FILE}"
  fi
fi

exec /usr/local/bin/paseo-docker-entrypoint "$@"
