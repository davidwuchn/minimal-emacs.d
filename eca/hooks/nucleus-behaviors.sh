#!/bin/bash
set -euo pipefail

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // empty' <<< "$INPUT")
SESSION_ID=$(jq -r '.chat_id // empty' <<< "$INPUT")

if [ -z "$PROMPT" ]; then
  exit 0
fi

# Use local behaviors directory (relative to hook location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ECA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BEHAVIORS_DIR="$ECA_DIR/behaviors"

# Fallback to nucleus if local doesn't exist
if [ ! -d "$BEHAVIORS_DIR" ]; then
  BEHAVIORS_DIR="$HOME/workspace/nucleus/behaviors"
fi

# Extract hashtags: #=mode, #quality, #technique
HASHTAGS=$(grep -oE '#[=a-zA-Z0-9_-]+' <<< "$PROMPT" | sort -u) || true

# State directory for persistence
STATE_DIR="$HOME/.config/eca/.behaviors"
STATE_FILE=""
if [ -n "$SESSION_ID" ]; then
  STATE_FILE="$STATE_DIR/$SESSION_ID"
fi

# No new hashtags - use persisted state
if [ -z "$HASHTAGS" ]; then
  if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
    ACTIVE=$(cat "$STATE_FILE")
    CONTEXT=""
    for TAG in $ACTIVE; do
      NAME="${TAG#\#=}"
      if [ "$NAME" = "$TAG" ]; then
        NAME="${TAG#\#}"
      fi
      for CATEGORY in modes qualities techniques; do
        FILE="$BEHAVIORS_DIR/$CATEGORY/$NAME/prompt.md"
        if [ -f "$FILE" ]; then
          [ -n "$CONTEXT" ] && CONTEXT+=$'\n\n'
          CONTEXT+="$(cat "$FILE")"
        fi
      done
    done
    if [ -n "$CONTEXT" ]; then
      jq -n --arg ctx "$CONTEXT" --arg active "$ACTIVE" '{
        additionalContext: ("Active behaviors: " + $active + "\n\n" + $ctx)
      }'
    fi
  fi
  exit 0
fi

# Reject multiple operating modes
MODE_COUNT=$(grep -c '^#=' <<< "$HASHTAGS") || true
if [ "$MODE_COUNT" -gt 1 ]; then
  MODE_TAGS=$(grep '^#=' <<< "$HASHTAGS" | tr '\n' ' ')
  echo "Error: multiple operating modes: ${MODE_TAGS%. }. Use one mode at a time." >&2
  exit 2
fi

# Separate mode from modifiers
MODE_TAG=$(grep '^#=' <<< "$HASHTAGS" | head -1) || true
MODE_TAG="${MODE_TAG#\#=}"
MOD_TAGS=$(grep -v '^#=' <<< "$HASHTAGS") || true

# Read mode content
MODE_CONTEXT=""
MISSING=""
if [ -n "$MODE_TAG" ]; then
  FILE="$BEHAVIORS_DIR/modes/$MODE_TAG/prompt.md"
  if [ -f "$FILE" ]; then
    MODE_CONTEXT="$(cat "$FILE")"
  else
    MISSING+=" #$MODE_TAG"
  fi
fi

# Read modifier content
MOD_CONTEXT=""
if [ -n "$MOD_TAGS" ]; then
  while IFS= read -r TAG; do
    [ -z "$TAG" ] && continue
    NAME="${TAG#\#}"
    FOUND=false
    for CATEGORY in qualities techniques; do
      FILE="$BEHAVIORS_DIR/$CATEGORY/$NAME/prompt.md"
      if [ -f "$FILE" ]; then
        FOUND=true
        [ -n "$MOD_CONTEXT" ] && MOD_CONTEXT+=$'\n\n'
        MOD_CONTEXT+="$(cat "$FILE")"
      fi
    done
    if [ "$FOUND" = false ]; then
      MISSING+=" $TAG"
    fi
  done <<< "$MOD_TAGS"
fi

if [ -n "$MISSING" ]; then
  echo "Warning: unknown behaviors:$MISSING" >&2
fi

# Persist active behaviors
if [ -n "$STATE_FILE" ]; then
  mkdir -p "$STATE_DIR"
  ACTIVE=""
  [ -n "$MODE_TAG" ] && [ -n "$MODE_CONTEXT" ] && ACTIVE+="#=$MODE_TAG"
  if [ -n "$MOD_TAGS" ]; then
    while IFS= read -r TAG; do
      [ -z "$TAG" ] && continue
      NAME="${TAG#\#}"
      for CATEGORY in qualities techniques; do
        if [ -f "$BEHAVIORS_DIR/$CATEGORY/$NAME/prompt.md" ]; then
          [ -n "$ACTIVE" ] && ACTIVE+=" "
          ACTIVE+="$TAG"
        fi
      done
    done <<< "$MOD_TAGS"
  fi
  echo "$ACTIVE" > "$STATE_FILE"
fi

# Build output
WRAPPED=""

if [ -n "$MODE_CONTEXT" ]; then
  WRAPPED+="<operating-mode>
$MODE_CONTEXT
</operating-mode>"
fi

if [ -n "$MOD_CONTEXT" ]; then
  if [ -n "$MODE_CONTEXT" ]; then
    WRAPPED+=$'\n\n'"<behavior-modifiers>
These modifiers apply WITHIN the operating mode's constraints.

$MOD_CONTEXT
</behavior-modifiers>"
  else
    WRAPPED+="<behavior-modifiers>
$MOD_CONTEXT
</behavior-modifiers>"
  fi
fi

if [ -n "$WRAPPED" ]; then
  WRAPPED+=$'\n\n'"These behaviors apply until superseded by new hashtags. During compaction, preserve the most recent <operating-mode> and <behavior-modifiers> blocks."
  jq -n --arg ctx "$WRAPPED" '{
    additionalContext: $ctx
  }'
fi

exit 0