#!/usr/bin/env bash
# Rebuilds the renderer into a temp dir and fails if it differs from assets/renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
node build.mjs "$tmp/renderer" >/dev/null
if ! diff -r "$tmp/renderer" ../assets/renderer >/dev/null; then
  echo "assets/renderer is stale: run 'cd renderer && npm run build' and commit the result." >&2
  diff -rq "$tmp/renderer" ../assets/renderer >&2 || true
  exit 1
fi
echo "assets/renderer is up to date."
