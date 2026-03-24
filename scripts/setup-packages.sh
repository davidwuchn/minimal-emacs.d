#!/usr/bin/env bash

# setup-packages.sh
# Initialize/update git submodules for fork packages
#
# Usage:
#   ./scripts/setup-packages.sh [--update]
#
# Options:
#   --update    Update submodules to latest from tracked branches

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "Setting up package submodules..."

# Check if .gitmodules exists
if [ ! -f ".gitmodules" ]; then
    echo "Error: No .gitmodules file found"
    exit 1
fi

# Initialize and update submodules
if [ "$1" = "--update" ]; then
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