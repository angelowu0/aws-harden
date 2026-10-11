#!/usr/bin/env bash
# Shared helpers sourced by every script in scripts/. Not meant to be run directly.
set -euo pipefail

# On Windows/Git Bash, MSYS silently rewrites any argument that looks like a POSIX
# absolute path (e.g. "/harbour-books/flask-app") into a Windows path before it reaches
# native .exe tools like aws.exe, corrupting it. This disables that rewriting. No-op elsewhere.
export MSYS_NO_PATHCONV=1

STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
mkdir -p "$STATE_DIR"

# CLI shorthand tag list reused across sns/cloudwatch/ec2/secretsmanager/iam --tags flags.
# Kept as an array (not a string) so a space in OWNER_TAG (e.g. "Angelo Wu") doesn't get
# word-split into a separate, invalid argument — always expand as "${TAGS[@]}".
TAGS=(
  "Key=Project,Value=${PROJECT_TAG}"
  "Key=Owner,Value=${OWNER_TAG}"
  "Key=Environment,Value=${ENVIRONMENT_TAG}"
)

state_write() { printf '%s' "$2" > "$STATE_DIR/$1"; }
state_read()  { [ -f "$STATE_DIR/$1" ] && cat "$STATE_DIR/$1" || true; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

require_cmd aws
