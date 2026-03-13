#!/bin/bash
# lint-elisp.sh - Run Emacs Lisp linters on .el files
#
# Usage: ./scripts/lint-elisp.sh [files...]
# If no files specified, lints all .el files in lisp/ and early-init.el/init.el

set -e

EMACS="${EMACS:-emacs}"
LISP_DIR="${LISP_DIR:-lisp}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((warnings++)) || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((errors++)) || true
}

# Check if package-lint is available
check_package_lint() {
    if ! $EMACS -Q --batch --eval "(require 'package-lint)" 2>/dev/null; then
        log_warn "package-lint not available, skipping package-lint checks"
        return 1
    fi
    return 0
}

# Run checkdoc on a file
run_checkdoc() {
    local file="$1"
    log_info "Running checkdoc on $file..."
    
    $EMACS -Q --batch \
        --eval "(require 'checkdoc)" \
        --eval "(setq checkdoc-arguments-in-order-flag nil)" \
        --eval "(setq checkdoc-force-docstrings-flag nil)" \
        -f batch-byte-compile "$file" 2>&1 | \
        grep -v "^Wrote " | \
        while IFS= read -r line; do
            if [[ "$line" =~ [Ee]rror|[Ff]atal ]]; then
                log_error "checkdoc: $line"
            elif [[ "$line" =~ [Ww]arn|[Ssuggestion] ]]; then
                log_warn "checkdoc: $line"
            fi
        done
}

# Run package-lint on a file
run_package_lint() {
    local file="$1"
    log_info "Running package-lint on $file..."
    
    $EMACS -Q --batch \
        --eval "(require 'package)" \
        --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
        --eval "(package-initialize)" \
        --eval "(unless (package-installed-p 'package-lint) (package-refresh-contents) (package-install 'package-lint))" \
        --eval "(require 'package-lint)" \
        -f package-lint-batch-and-exit "$file" 2>&1 | \
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                if [[ "$line" =~ [Ee]rror ]]; then
                    log_error "package-lint: $line"
                else
                    log_warn "package-lint: $line"
                fi
            fi
        done || true
}

# Run byte-compile with warnings
run_byte_compile() {
    local file="$1"
    log_info "Running byte-compile on $file..."
    
    $EMACS -Q --batch \
        -L . -L lisp -L lisp/modules \
        --eval "(setq byte-compile-error-on-warn nil)" \
        --eval "(setq byte-compile-warnings '(not obsolete free-vars unresolved))" \
        -f batch-byte-compile "$file" 2>&1 | \
        grep -v "^Wrote " | \
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                if [[ "$line" =~ [Ee]rror ]]; then
                    log_error "byte-compile: $line"
                elif [[ "$line" =~ [Ww]arning ]]; then
                    log_warn "byte-compile: $line"
                fi
            fi
        done
}

# Main
main() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        # Default: lint all .el files
        files=(
            early-init.el
            init.el
            $(find lisp -name "*.el" -type f 2>/dev/null || true)
        )
    fi
    
    log_info "Linting ${#files[@]} files..."
    echo ""
    
    local has_package_lint=0
    check_package_lint && has_package_lint=1
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Linting: $file"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            run_checkdoc "$file"
            run_byte_compile "$file"
            
            if [[ $has_package_lint -eq 1 ]]; then
                run_package_lint "$file"
            fi
            
            echo ""
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Summary: $errors errors, $warnings warnings"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ $errors -gt 0 ]]; then
        exit 1
    fi
}

main "$@"