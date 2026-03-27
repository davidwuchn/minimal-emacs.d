#!/usr/bin/env bash

# setup-packages.sh
# Initialize/update git submodules for fork packages
#
# Usage:
#   ./scripts/setup-packages.sh [OPTIONS]
#
# Options:
#   --update    Update submodules to latest from tracked branches
#   --force     Discard local changes in submodules before update
#   --clean     Remove and re-initialize all submodules

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

FORCE=false
CLEAN=false
UPDATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --update) UPDATE=true; shift ;;
        --force) FORCE=true; shift ;;
        --clean) CLEAN=true; shift ;;
        *) echo "Usage: $0 [--update] [--force] [--clean]"; exit 1 ;;
    esac
done

echo "Setting up package submodules..."

if [ ! -f ".gitmodules" ]; then
    echo "Error: No .gitmodules file found"
    exit 1
fi

# Clean option: remove and re-init
if [ "$CLEAN" = true ]; then
    echo "Removing all submodules..."
    git submodule deinit -f --all 2>/dev/null || true
fi

# Force option: discard local changes
if [ "$FORCE" = true ]; then
    echo "Discarding local changes in submodules..."
    git submodule foreach --recursive 'git checkout -- . 2>/dev/null || true; git clean -fd 2>/dev/null || true'
fi

# Initialize and update submodules
if [ "$UPDATE" = true ] || [ "$CLEAN" = true ]; then
    echo "Updating submodules to latest from tracked branches..."
    git submodule update --init --recursive
    git submodule update --remote --merge
else
    echo "Initializing submodules..."
    git submodule update --init --recursive
fi

# Generate autoloads for each submodule package
echo ""
echo "Generating autoloads..."
for pkg_dir in packages/*/; do
    if [ -d "$pkg_dir" ]; then
        pkg_name=$(basename "$pkg_dir")
        echo "  $pkg_name"
        emacs -Q --batch --eval "(progn
          (require 'package)
          (package-generate-autoloads '$pkg_name \"$pkg_dir\"))" 2>/dev/null || true
    fi
done

echo ""
echo "Package submodules:"
echo "NAME          BRANCH    COMMIT"
echo "----------------------------------------"
git submodule status | while read line; do
    commit=$(echo "$line" | awk '{print $1}' | sed 's/^+//;s/^-//;s/^//')
    path=$(echo "$line" | awk '{print $2}')
    name=$(basename "$path")
    if [ -d "$path" ]; then
        branch=$(cd "$path" && git branch --show-current 2>/dev/null || echo "?")
        printf "%-13s %-9s %s\n" "$name" "$branch" "$commit"
    fi
done

echo ""
echo "Done. Packages are in packages/"
echo "Use './scripts/setup-packages.sh --update' to update to latest versions."
echo "Use './scripts/setup-packages.sh --update --force' to discard local changes first."

# Install git hooks
if [ -f "$DIR/scripts/install-git-hooks.sh" ]; then
    echo ""
    "$DIR/scripts/install-git-hooks.sh"
fi