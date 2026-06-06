#!/usr/bin/env bash
# auto-gen-module-docs.sh — Generate module docs from Elisp headers

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="$DIR/lisp/modules"
DOCS_DIR="$DIR/mementum/knowledge/modules"

mkdir -p "$DOCS_DIR"

generate_doc() {
    local file="$1"
    local name=$(basename "$file" .el)
    local doc="$DOCS_DIR/$name.md"
    
    # Extract header comment (first comment block after ;;;)
    local header=$(sed -n '/^;;; /{s/^;;; //p;q}' "$file" 2>/dev/null || echo "")
    local purpose=$(sed -n '/^;; /{s/^;; //p;q}' "$file" 2>/dev/null || echo "")
    
    # Skip only if manually created (has real content, not just template)
    if [ -s "$doc" ] && [ "$(grep -c 'Auto-generated from code header' "$doc" 2>/dev/null || echo 0)" -eq 0 ]; then
        echo "  SKIP: $name (manually documented)"
        return
    fi
    
    # Count lines for size estimate
    local lines=$(wc -l < "$file" | tr -d ' ')
    
    cat > "$doc" <<EOF
# $(echo "$name" | sed 's/gptel-//g; s/-/ /g; s/\b\w/\u&/g')

## Purpose

${header:-TODO: Add description}

${purpose}

## File Stats

- **Lines**: $lines
- **Path**: \`$file\`

## Key Functions

$(grep -n "^(defun " "$file" 2>/dev/null | head -10 | sed 's/^(defun /- \`/; s/ .*/\`/' || echo "- TODO: Extract key functions")

## Dependencies

$(grep "^(require" "$file" 2>/dev/null | sed 's/^(require //; s/)$//' | head -10 | sed 's/^/- /' || echo "- TODO: List dependencies")

## Integration Points

- TODO: Document integration points

## See Also

- TODO: Link related modules

---
*Auto-generated from code header. Manual refinement needed.*
EOF
    
    echo "  DONE: $name ($lines lines)"
}

echo "Generating module docs..."
for file in "$MODULES_DIR"/*.el; do
    [ -f "$file" ] || continue
    generate_doc "$file"
done

echo ""
echo "Module docs generated in $DOCS_DIR"
echo "Run 'wc -l $DOCS_DIR/*.md' to see coverage."
