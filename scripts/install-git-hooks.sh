#!/bin/bash
#
# Install git hooks from scripts/git-hooks/ to .git/hooks/
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/git-hooks"
HOOKS_DEST="$(git rev-parse --git-dir)/hooks"

echo "Installing git hooks..."
echo "  Source: $HOOKS_SRC"
echo "  Dest:   $HOOKS_DEST"

for hook in "$HOOKS_SRC"/*; do
    if [[ -f "$hook" ]]; then
        hook_name=$(basename "$hook")
        cp "$hook" "$HOOKS_DEST/$hook_name"
        chmod +x "$HOOKS_DEST/$hook_name"
        echo "  Installed: $hook_name"
    fi
done

echo "Done."