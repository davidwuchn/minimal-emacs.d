#!/usr/bin/env bash

# verify-nucleus.sh
# Runs nucleus validation checks in batch mode.
# Can be used as a pre-commit hook or in CI.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMACS=${EMACS:-emacs}
ROOT_ELISP=$(printf '%s' "$DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')
TMP_ELISP=$(mktemp "${TMPDIR:-/tmp}/verify-nucleus.XXXXXX") || {
    echo "Failed to create temporary verifier script" >&2
    exit 1
}
RUNTIME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/verify-nucleus-runtime.XXXXXX") || {
    rm -f "$TMP_ELISP"
    echo "Failed to create isolated verifier runtime directory" >&2
    exit 1
}
WORKFLOW_SERVER="copilot-auto-workflow-verify-$(basename "$RUNTIME_DIR")"

cleanup() {
    rm -f "$TMP_ELISP"
    rm -rf "$RUNTIME_DIR"
}
trap cleanup EXIT

echo "Running Nucleus Tool Validations..."

echo ""
echo "[1/5] Verifying submodule sync..."
if [[ "${VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC:-0}" == "1" ]]; then
    echo "Skipping submodule sync checks (VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1)"
else
    "$DIR/scripts/check-submodule-sync.sh" --working-tree
    echo ""
    echo "[2/5] Verifying tracked submodule gitlinks..."
    "$DIR/scripts/check-submodule-sync.sh" --cached
fi

cat >"$TMP_ELISP" <<EOF
(setq package-archives nil)
(package-initialize 'no-activate)
(let* ((root "$ROOT_ELISP")
       (elpa-dir (expand-file-name "var/elpa" root))
       (paths (list
               (expand-file-name "gptel" elpa-dir)
               (expand-file-name "gptel-agent" elpa-dir)
               (expand-file-name "ai-code" elpa-dir)
               (expand-file-name "packages/gptel" root)
               (expand-file-name "packages/gptel-agent" root)
               (expand-file-name "packages/ai-code" root)
               (expand-file-name "lisp" root)
               (expand-file-name "lisp/modules" root))))
  (dolist (path paths)
    (when (file-directory-p path)
      (add-to-list 'load-path path))))
(require 'cl-lib)
(require 'gptel-config)
(require 'gptel-agent-tools)
(message "\\n[3/5] Verifying Agent Tool Contracts...")
(require 'nucleus-presets)
(condition-case err
    (progn
      (nucleus--validate-agent-tool-contracts)
      (message "✓ Agent tool contracts are valid."))
  (error
   (message "✗ Agent tool contracts validation failed: %s" (error-message-string err))
   (kill-emacs 1)))

(message "\\n[4/5] Verifying Tool Registrations...")
(require 'nucleus-tools-verify)
(let ((missing (cl-loop for item in (nucleus--verify-tools)
                        when (not (eq (cdr item) 'registered))
                        collect (car item))))
  (if missing
      (progn
        (message "✗ Tool registration validation failed. Missing/Duplicate tools: %s"
                 (mapconcat #'identity missing ", "))
        (kill-emacs 1))
    (message "✓ All tools correctly registered.")))

(message "\\n[5/5] Verifying Tool Signatures...")
(require 'nucleus-tools-validate)
(let* ((results (nucleus--validate-all-tools))
       (errors (cl-loop for (_ . (status . _)) in results count (eq status 'error))))
  (if (> errors 0)
      (progn
        (message "✗ Tool signature validation failed. Run 'M-x nucleus-validate-tool-signatures' for details.")
        (kill-emacs 1))
    (message "✓ All tool signatures are valid.")))
EOF

XDG_RUNTIME_DIR="$RUNTIME_DIR" \
TMPDIR="$RUNTIME_DIR" \
AUTO_WORKFLOW_EMACS_SERVER="$WORKFLOW_SERVER" \
$EMACS -Q --batch --init-directory="$DIR" \
       --eval "(let ((root (file-name-as-directory \"$ROOT_ELISP\"))) (setq minimal-emacs-user-directory root user-emacs-directory root))" \
       -l "$DIR/early-init.el" \
       -l "$TMP_ELISP"

echo -e "\nAll Nucleus validations passed successfully! ✓"
