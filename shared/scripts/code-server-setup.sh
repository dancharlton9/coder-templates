#!/bin/bash
# code-server-setup.sh — Install code-server, extensions, settings, and launch.
#
# Usage: /opt/coder/scripts/code-server-setup.sh [extension_file ...]
#
# Arguments:
#   extension_file  — Path(s) to text files containing one extension ID per line.
#                     Lines starting with # are ignored. Multiple files are merged.
#                     The core extensions file is always loaded automatically.
#
# Environment:
#   CODE_SERVER_PORT     — Port to listen on (default: 13337)
#   CODE_SERVER_FOLDER   — Folder to open (default: /home/coder/projects)
#   SETTINGS_SOURCE      — Path to settings.json template (default: /opt/coder/settings/code-server.json)

PORT="${CODE_SERVER_PORT:-13337}"
FOLDER="${CODE_SERVER_FOLDER:-/home/coder/projects}"
SETTINGS_SOURCE="${SETTINGS_SOURCE:-/opt/coder/settings/code-server.json}"
CORE_EXTENSIONS="/opt/coder/extensions/core.txt"

# ── Install code-server ───────────────────────────────────────────────────────
if ! command -v code-server &> /dev/null; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi

# ── Install extensions ────────────────────────────────────────────────────────
# Always load core extensions, then any additional files passed as arguments
EXTENSION_FILES=("$CORE_EXTENSIONS")
for f in "$@"; do
  [ -f "$f" ] && EXTENSION_FILES+=("$f")
done

for ext_file in "${EXTENSION_FILES[@]}"; do
  [ -f "$ext_file" ] || continue
  while IFS= read -r ext || [ -n "$ext" ]; do
    ext=$(echo "$ext" | xargs)  # trim whitespace
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    code-server --install-extension "$ext" || true
  done < "$ext_file"
done

# ── Settings ──────────────────────────────────────────────────────────────────
# Only write once — won't overwrite manual changes made inside code-server
SETTINGS_DIR=~/.local/share/code-server/User
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ] && [ -f "$SETTINGS_SOURCE" ]; then
  mkdir -p "$SETTINGS_DIR"
  cp "$SETTINGS_SOURCE" "$SETTINGS_FILE"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
code-server --auth none --port "$PORT" --host 0.0.0.0 > /tmp/code-server.log 2>&1 &
