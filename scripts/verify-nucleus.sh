#!/usr/bin/env bash

# verify-nucleus.sh
# Runs nucleus validation checks in batch mode.
# Can be used as a pre-commit hook or in CI.
#
# Loads early-init.el (for package paths) but NOT init.el/post-init.el,
# avoiding unrelated packages (evil, eca, etc.) that may break in batch.

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMACS=${EMACS:-emacs}

echo "Running Nucleus Tool Validations..."

$EMACS -Q --batch \
       -l "$DIR/early-init.el" \
       --eval "(progn
         (package-initialize)
         (unless (package-installed-p 'gptel)
           (package-refresh-contents)
           (package-install 'gptel))
         (add-to-list 'load-path (expand-file-name \"lisp\" \"$DIR\"))
         (add-to-list 'load-path (expand-file-name \"lisp/modules\" \"$DIR\"))
         (require 'gptel-config)
         (message \"\n[1/3] Verifying Agent Tool Contracts...\")
         (require 'nucleus-presets)
         (condition-case err
             (progn
               (nucleus--validate-agent-tool-contracts)
               (message \"✓ Agent tool contracts are valid.\"))
           (error
            (message \"✗ Agent tool contracts validation failed: %s\" (error-message-string err))
            (kill-emacs 1)))

         (message \"\n[2/3] Verifying Tool Registrations...\")
         (require 'nucleus-tools-verify)
         (let ((missing (cl-loop for item in (nucleus--verify-tools)
                                 when (not (eq (cdr item) 'registered))
                                 collect (car item))))
           (if missing
               (progn
                 (message \"✗ Tool registration validation failed. Missing/Duplicate tools: %s\" (mapconcat 'identity missing \", \"))
                 (kill-emacs 1))
             (message \"✓ All tools correctly registered.\")))

         (message \"\n[3/3] Verifying Tool Signatures...\")
         (require 'nucleus-tools-validate)
         (let* ((results (nucleus--validate-all-tools))
                (errors (cl-loop for (_ . (status . _)) in results count (eq status 'error))))
           (if (> errors 0)
               (progn
                 (message \"✗ Tool signature validation failed. Run 'M-x nucleus-validate-tool-signatures' for details.\")
                 (kill-emacs 1))
             (message \"✓ All tool signatures are valid.\"))))"

echo -e "\nAll Nucleus validations passed successfully! ✓"
