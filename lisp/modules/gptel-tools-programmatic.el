;;; gptel-tools-programmatic.el --- Programmatic tool orchestration -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Provides the Programmatic tool: a restricted Emacs Lisp orchestration layer
;; for chaining multiple existing tools inside one tool call.
;; Supplemental prompt guidance lives in assistant/prompts/tools/programmatic.md.

(require 'subr-x)

(require 'gptel-sandbox)

(defgroup gptel-tools-programmatic nil
  "Programmatic orchestration tool for gptel-agent."
  :group 'gptel)

(defun gptel-tools-programmatic--execute (callback code)
  "Execute restricted orchestration CODE and CALLBACK the final result."
  (gptel-sandbox-execute-async
   callback code
   (if (and (boundp 'gptel--preset)
            (eq gptel--preset 'gptel-plan))
       'readonly
     'agent)))

(defun gptel-tools-programmatic-register ()
  "Register the Programmatic tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Programmatic"
     :description
     "Execute restricted Emacs Lisp that orchestrates multiple existing tool calls. Use for tightly-coupled multi-step workflows; call tools as (tool-call \"ToolName\" :arg value ...); end the program with (result <expr>); not for arbitrary eval."
     :function #'gptel-tools-programmatic--execute
     :async t
     :args '((:name "code"
              :type string
              :description
              "Restricted Emacs Lisp program. Tool-call syntax is (tool-call \"ToolName\" :arg value ...). Must end with (result <expr>). Supported forms: setq, result, top-level tool-call, if/when/unless/not/and/or/progn, let/let*, mapcar, filter (sandbox-specific), comparisons. Data helpers: list/vector/append/length/car/cdr/nth/cons/assoc/alist-get/plist-get. String helpers: concat/format/split-string/string-join/string-trim/string-empty-p/string-match-p/substring."))
     :category "gptel-agent"
     :confirm t
     :include t)))

(provide 'gptel-tools-programmatic)

;;; gptel-tools-programmatic.el ends here
