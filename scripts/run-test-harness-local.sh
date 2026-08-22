#!/usr/bin/env bash
set -euo pipefail

# Serve the www directory so the Snack harness is the single source of truth.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WWW_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

HOST="${TEST_HARNESS_HOST:-127.0.0.1}"
PORT="${TEST_HARNESS_PORT:-8788}"
URL="http://${HOST}:${PORT}/test/test_snack.html"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to run the local test harness server."
  exit 1
fi

echo "Serving $WWW_DIR"
echo "Harness URL: $URL"

echo "Press Ctrl+C to stop."
cd "$WWW_DIR"
exec python3 -m http.server "$PORT" --bind "$HOST"
