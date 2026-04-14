#!/bin/bash
# clone-repos.sh — Clone comma-separated repos into ~/projects/<name>.
# After cloning, auto-detects and runs restore commands for known project types.
#
# Usage: /opt/coder/scripts/clone-repos.sh "git@github.com:org/repo1.git,git@github.com:org/repo2.git"

REPOS_CSV="$1"
PROJECTS_DIR=~/projects

[ -z "$REPOS_CSV" ] && echo "No repositories specified." && exit 0

mkdir -p "$PROJECTS_DIR"

IFS=',' read -ra REPOS <<< "$REPOS_CSV"
for REPO_URL in "${REPOS[@]}"; do
  REPO_URL=$(echo "$REPO_URL" | xargs)  # trim whitespace
  [ -z "$REPO_URL" ] && continue

  # Extract repo name: git@github.com:org/my-repo.git → my-repo
  REPO_NAME=$(basename "$REPO_URL" .git)
  REPO_DIR="$PROJECTS_DIR/$REPO_NAME"

  if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Cloning $REPO_URL into $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR" || { echo "WARNING: Failed to clone $REPO_URL"; continue; }
  fi

  # ── Auto-restore by project type ──────────────────────────────────────────

  # .NET
  if ls "$REPO_DIR"/*.sln 1>/dev/null 2>&1; then
    echo "Restoring .NET packages for $REPO_NAME..."
    dotnet restore "$REPO_DIR" || true
  fi

  # Node.js
  if [ -f "$REPO_DIR/package.json" ]; then
    echo "Installing npm packages for $REPO_NAME..."
    (cd "$REPO_DIR" && npm install) || true
  fi

  # Python
  if [ -f "$REPO_DIR/requirements.txt" ]; then
    echo "Installing Python packages for $REPO_NAME..."
    (cd "$REPO_DIR" && pip install -r requirements.txt --break-system-packages) || true
  fi

  # Go
  if [ -f "$REPO_DIR/go.mod" ]; then
    echo "Downloading Go modules for $REPO_NAME..."
    (cd "$REPO_DIR" && go mod download) || true
  fi
done
