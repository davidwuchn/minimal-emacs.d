#!/usr/bin/env bash

# setup-packages.sh
# Install required packages from Git for minimal-emacs.d
#
# Usage:
#   ./scripts/setup-packages.sh [--force]
#
# Options:
#   --force    Reinstall even if already installed

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ELPA_DIR="$DIR/var/elpa"
FORCE="${1:-}"

echo "Setting up packages in $ELPA_DIR..."

# Create elpa directory if needed
mkdir -p "$ELPA_DIR"

# Packages to install: name, URL, branch
PACKAGES=(
  "gptel|https://github.com/karthink/gptel|master"
  "gptel-agent|https://github.com/karthink/gptel-agent|master"
)

cleanup_old_versions() {
  local NAME="$1"
  local ELPA_DIR="$2"
  # Remove old versioned directories (e.g., gptel-0.9.0, gptel-agent-1.0.0)
  find "$ELPA_DIR" -maxdepth 1 -type d -name "${NAME}-[0-9]*" -exec rm -rf {} \; 2>/dev/null || true
}

for pkg in "${PACKAGES[@]}"; do
  IFS='|' read -r NAME URL BRANCH <<< "$pkg"
  TARGET_DIR="$ELPA_DIR/$NAME"
  
  if [ -d "$TARGET_DIR/.git" ] && [ -z "$FORCE" ]; then
    echo "✓ $NAME already installed (use --force to reinstall)"
    cleanup_old_versions "$NAME" "$ELPA_DIR"
    continue
  fi
  
  echo "Installing $NAME from $URL (branch: $BRANCH)..."
  
  # Remove existing directory
  rm -rf "$TARGET_DIR"
  
  # Clone with depth 1 for faster download
  git clone --depth 1 --branch "$BRANCH" "$URL" "$TARGET_DIR"
  
  # Generate autoloads for git-cloned packages
  emacs -Q --batch --eval "(progn
    (require 'package)
    (package-generate-autoloads '$NAME \"$TARGET_DIR\"))" 2>/dev/null || true
  
  # Cleanup old versioned directories after successful install
  cleanup_old_versions "$NAME" "$ELPA_DIR"
  
  echo "✓ $NAME installed"
done

echo ""
echo "All packages installed in var/elpa/:"
ls -d "$ELPA_DIR"/gptel* 2>/dev/null | xargs -n1 basename