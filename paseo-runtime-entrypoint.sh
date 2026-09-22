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

// Remove the superseded split-role providers. The delivery workflow now uses
// one normal OpenCode Dev session and one restricted OpenCode Audit session.
delete config.agents.providers["opencode-qa"];
delete config.agents.providers["opencode-security"];
delete config.agents.providers["opencode-orchestrator"];

config.agents.providers["opencode-audit"] = {
  extends: "opencode",
  label: "OpenCode Audit",
  description:
    "Independent audit/delivery provider for browser QA, security scanning, code review, and Draft PR delivery without source editing.",
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

config.daemon ??= {};
let currentProfiles = Array.isArray(config.daemon.agentProfiles)
  ? config.daemon.agentProfiles
  : [];

// Remove profiles that belonged to the old QA/Security/Orchestrator split,
// plus the old Review profile so it can be replaced deterministically below.
const retiredProviders = new Set([
  "opencode-qa",
  "opencode-security",
  "opencode-orchestrator"
]);
currentProfiles = currentProfiles.filter((profile) => {
  if (!profile || typeof profile !== "object") return true;
  if (retiredProviders.has(profile.provider)) return false;
  if (profile.id === "konsultanedu-delivery-orchestrator") return false;
  if (profile.id === "konsultanedu-review-audit") return false;
  if (profile.name === "Review") return false;
  return true;
});

const reviewModel = (process.env.OPENCODE_CONFIG ?? "").endsWith("opencode.vps.json")
  ? "9router/paseo-review"
  : "9router/cx/gpt-5.6-sol-review";

currentProfiles.push({
  id: "konsultanedu-review-audit",
  name: "Review",
  provider: "opencode-audit",
  model: reviewModel,
  modeId: "review",
  notes:
    "Independent Audit session: run functional/browser QA, security scans, diff/code review, then checkpoint commit, push, and Draft PR only after every gate passes. Never edit source files."
});

config.daemon.agentProfiles = currentProfiles;

fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
NODE
  if [[ "$(id -u)" == "0" ]]; then
    chown paseo:paseo "${PASEO_CONFIG_FILE}"
  fi
fi

exec /usr/local/bin/paseo-docker-entrypoint "$@"
