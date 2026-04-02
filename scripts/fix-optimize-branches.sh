#!/usr/bin/env bash

# Fix optimize branches that failed to push
# Pushes local optimize branches to origin with --force-with-lease

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Fix Optimize Branch Push Failures ==="
echo

# Count branches
LOCAL_COUNT=$(git branch | grep -c "optimize/" || echo 0)
REMOTE_COUNT=$(git branch -r | grep -c "optimize/" || echo 0)

echo "Local optimize branches: $LOCAL_COUNT"
echo "Remote optimize branches: $REMOTE_COUNT"
echo

if [ "$LOCAL_COUNT" -eq 0 ]; then
    echo "No local optimize branches to push."
    exit 0
fi

# Get list of local optimize branches
BRANCHES=$(git branch | grep "optimize/" | sed 's/^[* ]*//')

echo "Pushing $LOCAL_COUNT branches to origin..."
echo

PUSHED=0
FAILED=0

for branch in $BRANCHES; do
    echo -n "  $branch ... "
    
    # Try normal push first
    if git push origin "$branch" 2>/dev/null; then
        echo "✓ pushed"
        ((PUSHED++)) || true
    else
        # Retry with force-with-lease
        if git push --force-with-lease origin "$branch" 2>/dev/null; then
            echo "✓ force-pushed"
            ((PUSHED++)) || true
        else
            echo "✗ failed"
            ((FAILED++)) || true
        fi
    fi
done

echo
echo "=== Summary ==="
echo "Pushed: $PUSHED"
echo "Failed: $FAILED"
echo

# Verify remote now has branches
NEW_REMOTE=$(git branch -r | grep -c "optimize/" || echo 0)
echo "Remote optimize branches now: $NEW_REMOTE"

if [ "$NEW_REMOTE" -gt 0 ]; then
    echo
    echo "✓ Branches are now on origin"
    echo "  Next: Run staging flow for kept experiments"
fi