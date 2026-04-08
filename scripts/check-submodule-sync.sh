#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

MODE="treeish"
TREEISH="HEAD"
TEMP_GITMODULES=""

usage() {
    cat <<'EOF'
Usage: ./scripts/check-submodule-sync.sh [--working-tree | --cached | --treeish REV]

Validate that each submodule:
1. points to a commit that exists on its configured remote, and
2. matches the head of the branch configured in .gitmodules.

Modes:
  --working-tree   Check currently checked-out submodule HEADs.
  --cached         Check staged gitlinks and staged .gitmodules.
  --treeish REV    Check gitlinks recorded in REV (default: HEAD).
EOF
}

cleanup() {
    if [[ -n "$TEMP_GITMODULES" && -f "$TEMP_GITMODULES" ]]; then
        rm -f "$TEMP_GITMODULES"
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --working-tree)
            MODE="working-tree"
            shift
            ;;
        --cached)
            MODE="cached"
            shift
            ;;
        --treeish)
            MODE="treeish"
            TREEISH="${2:?missing revision for --treeish}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

load_gitmodules_file() {
    case "$MODE" in
        working-tree)
            if [[ -f .gitmodules ]]; then
                printf '%s\n' ".gitmodules"
            fi
            ;;
        cached)
            TEMP_GITMODULES="$(mktemp "${TMPDIR:-/tmp}/gitmodules-index.XXXXXX")"
            if git show ':.gitmodules' >"$TEMP_GITMODULES" 2>/dev/null && [[ -s "$TEMP_GITMODULES" ]]; then
                printf '%s\n' "$TEMP_GITMODULES"
            fi
            ;;
        treeish)
            TEMP_GITMODULES="$(mktemp "${TMPDIR:-/tmp}/gitmodules-tree.XXXXXX")"
            if git show "${TREEISH}:.gitmodules" >"$TEMP_GITMODULES" 2>/dev/null && [[ -s "$TEMP_GITMODULES" ]]; then
                printf '%s\n' "$TEMP_GITMODULES"
            fi
            ;;
    esac
}

submodule_sha() {
    local path="$1"

    case "$MODE" in
        working-tree)
            if [[ ! -d "$path" ]]; then
                return 1
            fi
            local dot_git="$path/.git"
            if [[ ! -e "$dot_git" ]]; then
                return 1
            fi
            git -C "$path" rev-parse HEAD 2>/dev/null
            ;;
        cached)
            git ls-files --stage -- "$path" | awk '$1 == "160000" { print $2; exit }'
            ;;
        treeish)
            git ls-tree "$TREEISH" -- "$path" | awk '$1 == "160000" { print $3; exit }'
            ;;
    esac
}

remote_contains_commit() {
    local url="$1"
    local sha="$2"
    local tmp_git_dir

    tmp_git_dir="$(mktemp -d "${TMPDIR:-/tmp}/submodule-remote-check.XXXXXX")"
    git -c init.defaultBranch=main init --bare -q "$tmp_git_dir" >/dev/null 2>&1

    if git --git-dir="$tmp_git_dir" fetch --quiet --depth=1 "$url" "$sha" >/dev/null 2>&1; then
        rm -rf "$tmp_git_dir"
        return 0
    fi

    rm -rf "$tmp_git_dir"
    return 1
}

describe_source() {
    case "$MODE" in
        working-tree) printf '%s\n' "working tree" ;;
        cached) printf '%s\n' "staged index" ;;
        treeish) printf '%s\n' "tree ${TREEISH}" ;;
    esac
}

GITMODULES_FILE="$(load_gitmodules_file || true)"
if [[ -z "${GITMODULES_FILE:-}" || ! -s "$GITMODULES_FILE" ]]; then
    echo "No .gitmodules found in $(describe_source); nothing to check."
    exit 0
fi

FAILURES=0
CHECKED=0

echo "Checking submodule sync against tracked remote heads in $(describe_source)..."

while IFS= read -r path_key; do
    [[ -n "$path_key" ]] || continue

    path="$(git config --file "$GITMODULES_FILE" --get "$path_key")"
    section="${path_key%.path}"
    url="$(git config --file "$GITMODULES_FILE" --get "${section}.url" || true)"
    branch="$(git config --file "$GITMODULES_FILE" --get "${section}.branch" || true)"
    sha="$(submodule_sha "$path" || true)"

    if [[ -z "$url" ]]; then
        echo "ERROR: $path has no configured remote URL in .gitmodules."
        FAILURES=$((FAILURES + 1))
        continue
    fi

    if [[ -z "$branch" ]]; then
        echo "ERROR: $path has no configured branch in .gitmodules."
        FAILURES=$((FAILURES + 1))
        continue
    fi

    if [[ -z "$sha" ]]; then
        case "$MODE" in
            working-tree)
                echo "ERROR: $path is missing locally or is not a valid git checkout."
                ;;
            *)
                echo "ERROR: $path has no gitlink recorded in $(describe_source)."
                ;;
        esac
        FAILURES=$((FAILURES + 1))
        continue
    fi

    remote_head="$(git ls-remote "$url" "refs/heads/$branch" | awk 'NR == 1 { print $1 }')"
    if [[ -z "$remote_head" ]]; then
        echo "ERROR: $path tracks refs/heads/$branch, but that ref was not found at $url."
        FAILURES=$((FAILURES + 1))
        continue
    fi

    if [[ "$sha" == "$remote_head" ]]; then
        printf 'OK: %s -> %s matches %s (%s)\n' "$path" "$sha" "$branch" "$url"
        CHECKED=$((CHECKED + 1))
        continue
    fi

    if remote_contains_commit "$url" "$sha"; then
        echo "ERROR: $path is pinned to $sha, but tracked branch $branch is at $remote_head."
        echo "       Sync the submodule to the latest remote head before committing or pushing."
    else
        echo "ERROR: $path points to missing gitlink $sha."
        echo "       Remote $url does not contain that commit; tracked branch $branch is at $remote_head."
    fi

    FAILURES=$((FAILURES + 1))
done < <(git config --file "$GITMODULES_FILE" --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null | sort || true)

if (( FAILURES > 0 )); then
    echo ""
    echo "Submodule sync check failed with $FAILURES problem(s)."
    exit 1
fi

echo ""
echo "All $CHECKED submodule(s) match their tracked remote heads."
