#!/bin/bash
# push-template.sh — Bundle shared files into a template and push to Coder.
#
# Usage: ./push-template.sh <template-name>
# Example: ./push-template.sh dotnet-angular

set -euo pipefail

TEMPLATE_NAME="${1:?Usage: ./push-template.sh <template-name>}"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/$TEMPLATE_NAME"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: Template directory not found: $TEMPLATE_DIR"
  exit 1
fi

echo "Bundling shared/ into $TEMPLATE_DIR..."
cp -r "$REPO_ROOT/shared" "$TEMPLATE_DIR/shared"

cleanup() {
  echo "Cleaning up bundled files..."
  rm -rf "$TEMPLATE_DIR/shared"
}
trap cleanup EXIT

echo "Pushing template '$TEMPLATE_NAME'..."
coder templates push "$TEMPLATE_NAME" --directory "$TEMPLATE_DIR"
