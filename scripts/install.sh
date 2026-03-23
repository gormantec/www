#!/usr/bin/env bash
set -euo pipefail

# install.sh
#
# Intended usage:
#   curl -fsSL https://www.gormantec.com/scripts/install.sh | \
#     bash -s -- --github-token "$GITHUB_TOKEN" --repo <owner/repo> [--ref <ref>]
#
# Assumptions:
# - This script can be shared publicly, but requires a GitHub token with read access to the repo to function.
# - The repo must contain an OpenClaw plugin with a valid openclaw.plugin.json
# - Run from /home/openclaw (or your OpenClaw workspace dir)
# - .openclaw already exists in the current directory
# - openclaw CLI is installed and on PATH
# - Node >= 22.16.0 (required by openclaw@2026.3.13)

SCRIPT_NAME="install.sh"

log() { printf "%s\n" "$*"; }
warn() { printf "%s\n" "WARN: $*" >&2; }
die() { printf "%s\n" "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

semver_ge() {
  # Returns 0 if $1 >= $2
  # shellcheck disable=SC2206
  local a=(${1//./ }) b=(${2//./ })
  for i in 0 1 2; do
    local ai="${a[i]:-0}" bi="${b[i]:-0}"
    if ((ai > bi)); then return 0; fi
    if ((ai < bi)); then return 1; fi
  done
  return 0
}

usage() {
  cat <<EOF
$SCRIPT_NAME

Installs an OpenClaw plugin from a GitHub repo tarball and enables it.

Options:
  --github-token <token>   (required) GitHub token with read access to the repo
  --repo <owner/repo>      (required) GitHub repo to download
  --ref <ref>              Git ref (tag/branch/sha) (default: main)
  --install-dir <path>     Override install directory (default: ./\.openclaw/extensions/<plugin-id>)
  --no-build               Skip npm install/build (not recommended)
  --no-restart             Do not restart OpenClaw gateway
  -h, --help               Show help

Example:
  $SCRIPT_NAME --github-token "..." --repo gormantec/openclaw_plugin_dashboard --ref main
EOF
}

GITHUB_TOKEN=""
REPO=""
REF="main"
NO_BUILD="false"
NO_RESTART="false"
INSTALL_DIR_OVERRIDE=""

OPENCLAW_WORKDIR="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-token)
      GITHUB_TOKEN="${2:-}"; shift 2 ;;
    --repo)
      REPO="${2:-}"; shift 2 ;;
    --ref)
      REF="${2:-}"; shift 2 ;;
    --install-dir)
      INSTALL_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --no-build)
      NO_BUILD="true"; shift 1 ;;
    --no-restart)
      NO_RESTART="true"; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown arg: $1 (use --help)" ;;
  esac
done

[[ -n "$GITHUB_TOKEN" ]] || die "--github-token is required"
[[ -n "$REPO" ]] || die "--repo is required"

require_cmd curl
require_cmd tar
require_cmd node
require_cmd npm
require_cmd openclaw

if [[ ! -d "$OPENCLAW_WORKDIR/.openclaw" ]]; then
  die "expected .openclaw in current dir ($OPENCLAW_WORKDIR). Run this from /home/openclaw (or your OpenClaw workspace)."
fi

NODE_VERSION_RAW="$(node -v | sed 's/^v//')"
if ! semver_ge "$NODE_VERSION_RAW" "22.16.0"; then
  die "Node $NODE_VERSION_RAW detected, but OpenClaw 2026.3.13 requires Node >= 22.16.0"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Installing OpenClaw plugin"
log "- Repo: $REPO"
log "- Ref:  $REF"

# Download repo tarball from GitHub API (works for private repos with token)
TARBALL_URL="https://api.github.com/repos/$REPO/tarball/$REF"
ARCHIVE="$TMP_DIR/plugin.tgz"

log "Downloading from GitHub..."
# Note: use Authorization header; do not echo token.
curl -fsSL \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$TARBALL_URL" \
  -o "$ARCHIVE"

log "Extracting..."
EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

TOP_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ -n "$TOP_DIR" ]] || die "unexpected archive layout"

MANIFEST_PATH="$TOP_DIR/openclaw.plugin.json"
if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "NOT a plugin"
  exit 2
fi

PLUGIN_NAME="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const m=JSON.parse(fs.readFileSync(p,"utf8")); console.log(m.name || "");' "$MANIFEST_PATH")"
PLUGIN_ID="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const m=JSON.parse(fs.readFileSync(p,"utf8")); console.log(m.id || "");' "$MANIFEST_PATH")"

if [[ -z "$PLUGIN_ID" ]]; then
  die "openclaw.plugin.json exists but is missing required field: id"
fi

if [[ -z "$PLUGIN_NAME" ]]; then
  PLUGIN_NAME="$PLUGIN_ID"
fi

echo "Installing $PLUGIN_NAME"

INSTALL_DIR="$OPENCLAW_WORKDIR/.openclaw/extensions/$PLUGIN_ID"
if [[ -n "$INSTALL_DIR_OVERRIDE" ]]; then
  INSTALL_DIR="$INSTALL_DIR_OVERRIDE"
fi

log "- Install dir: $INSTALL_DIR"

mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy all contents from extracted top dir into install dir
# (Avoid rsync dependency)
(
  shopt -s dotglob
  cp -R "$TOP_DIR"/* "$INSTALL_DIR"/
)

if [[ "$NO_BUILD" != "true" ]]; then
  log "Installing npm dependencies (no lifecycle scripts)..."
  (cd "$INSTALL_DIR" && npm install --ignore-scripts)

  # Optional: build if the plugin defines it (detect via package.json, not npm output)
  HAS_BUILD_SCRIPT="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); console.log(p.scripts && p.scripts.build ? "yes" : "no");' "$INSTALL_DIR/package.json")"
  if [[ "$HAS_BUILD_SCRIPT" == "yes" ]]; then
    log "Running build..."
    (cd "$INSTALL_DIR" && npm run build)
  else
    warn "No build script found; skipping build"
  fi
else
  warn "Skipping build (--no-build). If the plugin requires compilation, it may not load."
fi


# If the user is running a workspace-local install (./.openclaw exists), pin trust
# by adding the plugin id to plugins.allow in the workspace config when possible.
WORKSPACE_CONFIG_JSON="$OPENCLAW_WORKDIR/.openclaw/openclaw.json"
if [[ -f "$WORKSPACE_CONFIG_JSON" ]]; then
  log "Updating plugins.allow in $WORKSPACE_CONFIG_JSON..."
  openclaw config set plugins.allow[] "$PLUGIN_ID"
  echo "Updated plugins.allow in workspace config to include $PLUGIN_ID"
fi


# --- Install systemd service (if applicable) ---

if node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("'"$INSTALL_DIR"'/package.json","utf8"));process.exit((p.scripts && p.scripts["install:service"]) ? 0 : 1);'; then
  echo "Installing plugin systemd service..."
  cd $INSTALL_DIR
  npm run install:service
fi

log "Enabling plugin in OpenClaw..."
openclaw plugins enable "$PLUGIN_ID" >/dev/null

if [[ "$NO_RESTART" != "true" ]]; then
  log "Restarting OpenClaw gateway..."
  openclaw gateway restart
else
  warn "Skipped gateway restart (--no-restart). Restart is required to load the plugin."
fi

log "Done."

