;;; gptel-sandbox.el --- Restricted tool orchestration sandbox -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Restricted evaluator for the Programmatic tool. It does not expose general
;; Emacs Lisp evaluation. Instead it supports a tiny statement/expression subset
;; for serial orchestration of existing non-confirming tools.

(require 'cl-lib)
(require 'pp)
(require 'seq)
(require 'subr-x)

(require 'gptel nil t)

;;; Customization

(defgroup gptel-sandbox nil
  "Restricted sandbox for programmatic tool orchestration."
  :group 'gptel)

(defcustom my/gptel-programmatic-timeout 15
  "Seconds before Programmatic execution is force-stopped."
  :type 'integer
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-max-tool-calls 25
  "Maximum nested tool calls allowed in a Programmatic execution."
  :type 'integer
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-result-limit 4000
  "Max characters to return inline from Programmatic execution.
Results longer than this are truncated and the full text is saved to a temp
file."
  :type 'integer
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-allowed-tools
  '("Read" "Grep" "Glob"
    "Edit" "ApplyPatch"
    "Code_Map" "Code_Inspect" "Code_Replace" "Code_Usages" "Diagnostics"
    "describe_symbol" "get_symbol_source" "find_buffers_and_recent")
  "Tool names allowed inside Programmatic execution.
The initial v1 slice focuses on read-mostly tools plus preview-backed patch
editors (`Edit`, `ApplyPatch`, `Code_Replace`)."
  :type '(repeat string)
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-readonly-tools
  '("Read" "Grep" "Glob"
    "Code_Map" "Code_Inspect" "Code_Usages" "Diagnostics"
    "describe_symbol" "get_symbol_source" "find_buffers_and_recent")
  "Tool names allowed inside Programmatic when running in readonly mode.
This profile is used by `gptel-plan` and excludes mutating or confirming tools."
  :type '(repeat string)
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-confirming-tools
  '("Edit" "ApplyPatch" "Code_Replace")
  "Tool names allowed to request confirmation inside Programmatic.
These tools keep their own preview/apply flow after the initial nested
confirmation step."
  :type '(repeat string)
  :group 'gptel-sandbox)

(defvar gptel-sandbox-confirm-function #'gptel-sandbox--default-confirm-tool
  "Function used to confirm nested Programmatic tool calls.
Called with TOOL-SPEC, ARG-VALUES, and CALLBACK. CALLBACK must be invoked with
non-nil to continue or nil to reject.")

(defvar gptel-sandbox-aggregate-confirm-function
  #'gptel-sandbox--default-aggregate-confirm
  "Function used to preview/confirm multi-step mutating Programmatic runs.
Called with PLAN and CALLBACK. CALLBACK must be invoked with non-nil to
continue or nil to reject.")

(defvar gptel-sandbox-profile nil
  "Dynamic sandbox capability profile for Programmatic execution.
When nil, `gptel-sandbox--current-profile' infers the profile from the active
gptel preset.")

;;; Internal Helpers

(defvar gptel-sandbox--missing-marker (make-symbol "gptel-sandbox-missing")
  "Sentinel value for detecting missing symbol lookups in sandbox env.")

(defun gptel-sandbox--parse-forms (code)
  "Parse CODE into a list of Lisp forms."
  (let ((forms nil)
        (pos 0)
        (len (length code)))
    (while (< pos len)
      (condition-case err
          (let* ((parsed (read-from-string code pos))
                 (form (car parsed))
                 (next-pos (cdr parsed)))
            (push form forms)
            (setq pos next-pos))
        (end-of-file
         (if (string-match-p "\\`[ \t\n\r]*\\(?:;[^\n]*\n?[ \t\n\r]*\\)*\\'"
                             (substring code pos))
             (setq pos len)
           (error "Invalid program syntax near offset %d: %s"
                  pos (error-message-string err))))
        (error
         (error "Invalid program syntax near offset %d: %s"
                pos (error-message-string err)))))
    (nreverse forms)))

(defun gptel-sandbox--make-env ()
  "Create a fresh sandbox environment."
  (let ((env (make-hash-table :test #'eq)))
    (puthash 't t env)
    (puthash 'nil nil env)
    env))

(defun gptel-sandbox--copy-env (env)
  "Return a shallow copy of ENV."
  (let ((copy (make-hash-table :test #'eq)))
    (maphash (lambda (key value)
               (puthash key value copy))
             env)
    copy))

(defun gptel-sandbox--bind-result (symbol value env)
  "Bind SYMBOL to VALUE in ENV, also updating `_` and `it`."
  (puthash symbol value env)
  (puthash '_ value env)
  (puthash 'it value env))

(defun gptel-sandbox--bind-last-value (value env)
  "Bind VALUE to last-result placeholders `_` and `it` in ENV."
  (puthash '_ value env)
  (puthash 'it value env))

(defun gptel-sandbox--normalize-binding (binding)
  "Normalize a let-style BINDING into `(SYMBOL VALUE-FORM)'."
  (cond
   ((symbolp binding)
    (list binding nil))
   ((and (consp binding)
         (symbolp (car binding))
         (null (cddr binding)))
    binding)
   (t
    (error "Invalid binding in Programmatic sandbox: %S" binding))))

(defun gptel-sandbox--validate-setq-pairs (pairs)
  "Validate PAIRS as symbol/value pairs, returning (SYMBOL . VALUE-FORM) entries.
Raises an error if PAIRS is malformed."
  (unless (cl-evenp (length pairs))
    (error "Programmatic setq requires symbol/value pairs"))
  (cl-loop
   while pairs
   for symbol = (pop pairs)
   for value-form = (pop pairs)
   do (unless (symbolp symbol)
        (error "Programmatic setq target must be a symbol, got: %S" symbol))
   collect (cons symbol value-form)))

(defun gptel-sandbox--eval-setq-pairs (pairs env)
  "Evaluate setq PAIRS in ENV and return the final assigned value."
  (let ((value nil))
    (dolist (entry (gptel-sandbox--validate-setq-pairs pairs))
      (let ((symbol (car entry))
            (value-form (cdr entry)))
        (setq value (gptel-sandbox--eval-expr value-form env))
        (gptel-sandbox--bind-result symbol value env)))
    value))

(defun gptel-sandbox--eval-let-binding (binding env)
  "Evaluate a single BINDING in ENV, returning (SYMBOL . VALUE)."
  (pcase-let ((`(,symbol ,value-form)
               (gptel-sandbox--normalize-binding binding)))
    (cons symbol (gptel-sandbox--eval-expr value-form env))))

(defun gptel-sandbox--eval-let (bindings body env sequentialp)
  "Evaluate let-style BINDINGS and BODY in ENV.
When SEQUENTIALP is non-nil, evaluate bindings sequentially like `let*'."
  (let ((child-env (gptel-sandbox--copy-env env)))
    (if sequentialp
        (dolist (binding bindings)
          (pcase-let ((`(,symbol ,value-form)
                       (gptel-sandbox--normalize-binding binding)))
            (let ((value (gptel-sandbox--eval-expr value-form child-env)))
              (puthash symbol value child-env))))
      (dolist (binding bindings)
        (pcase-let ((`(,symbol . ,value)
                     (gptel-sandbox--eval-let-binding binding env)))
          (puthash symbol value child-env))))
    (let ((value nil))
      (dolist (form body value)
        (setq value (gptel-sandbox--eval-expr form child-env))))))

(defun gptel-sandbox--eval-map-like (expr env keep-original)
  "Evaluate sandbox `mapcar' or `filter' EXPR in ENV.
When KEEP-ORIGINAL is non-nil, keep original items whose body is truthy;
otherwise collect each mapped result.

Supported shape:
  (mapcar (lambda (item) BODY...) LIST)
  (filter (lambda (item) BODY...) LIST)"
  (let ((op-name (if keep-original "filter" "mapcar")))
    (pcase expr
      (`(,_ (lambda (,arg) . ,body) ,list-expr)
       (unless (symbolp arg)
         (error "Programmatic %s lambda arg must be a symbol" op-name))
       (let ((items (gptel-sandbox--eval-expr list-expr env))
             (results nil))
         (unless (listp items)
           (error "Programmatic %s expects a list input" op-name))
         (dolist (item items (nreverse results))
           ;; Each lambda invocation needs an isolated child env so `setq'
           ;; state does not leak between map/filter iterations.
           (let ((child-env (gptel-sandbox--copy-env env)))
             (puthash arg item child-env)
             (let ((value nil))
               (dolist (form body)
                 (setq value (gptel-sandbox--eval-expr form child-env)))
               (if keep-original
                   (when value
                     (push item results))
                 (push value results)))))))
      (_
       (error "Programmatic %s requires (lambda (item) ...) and a list" op-name)))))

(defun gptel-sandbox--lookup (symbol env)
  "Look up SYMBOL in ENV or signal an error."
  (let ((value (gethash symbol env gptel-sandbox--missing-marker)))
    (if (eq value gptel-sandbox--missing-marker)
        (error "Unknown symbol in Programmatic sandbox: %S" symbol)
      value)))

(defun gptel-sandbox--eval-sequential (forms env)
  "Evaluate FORMS sequentially in ENV, returning the last result."
  (let ((value nil))
    (dolist (form forms value)
      (setq value (gptel-sandbox--eval-expr form env)))))

(defun gptel-sandbox--short-circuit-eval (forms env initial-value stop-pred)
  "Evaluate FORMS sequentially with short-circuit logic.
INITIAL-VALUE is the starting value. STOP-PRED is called on each result;
when non-nil, evaluation short-circuits and returns that result.
Used by `and' and `or' to share short-circuit evaluation logic."
  (unless (functionp stop-pred)
    (error "Programmatic short-circuit requires a function predicate, got: %S" stop-pred))
  (let ((value initial-value))
    (catch 'gptel-sandbox-short-circuit
      (dolist (form forms value)
        (setq value (gptel-sandbox--eval-expr form env))
        (when (funcall stop-pred value)
          (throw 'gptel-sandbox-short-circuit value))))))

(defun gptel-sandbox--apply-builtin (func args env)
  "Apply built-in function FUNC to evaluated ARGS in ENV."
  (let ((evaluated-args (mapcar (lambda (arg) (gptel-sandbox--eval-expr arg env)) args)))
    (condition-case err
        (apply func evaluated-args)
      (error
       (error "Programmatic builtin %s failed: %s" func (error-message-string err))))))

(defun gptel-sandbox--eval-expr (expr env)
  "Evaluate pure sandbox expression EXPR in ENV.
This evaluator intentionally excludes general function application and only
supports a small, explicit whitelist of pure operations."
  (cond
   ((or (stringp expr) (numberp expr) (keywordp expr) (vectorp expr)) expr)
   ((memq expr '(t nil)) expr)
   ((symbolp expr) (gptel-sandbox--lookup expr env))
   ((not (consp expr)) expr)
   (t
    (pcase (car expr)
      ('quote
       (cadr expr))
      ('if
          (let ((args (cdr expr)))
            (unless (>= (length args) 2)
              (error "Programmatic if requires at least 2 arguments (condition and then-form), got: %d" (length args)))
            (let ((cond-result (gptel-sandbox--eval-expr (car args) env)))
              (if cond-result
                  (gptel-sandbox--eval-expr (cadr args) env)
                (gptel-sandbox--eval-expr (nth 2 args) env)))))
      ('setq
       (gptel-sandbox--eval-setq-pairs (cdr expr) env))
      ('when
       (let ((args (cdr expr)))
         (unless (>= (length args) 1)
           (error "Programmatic when requires at least 1 argument (condition), got: %d" (length args)))
         (when (gptel-sandbox--eval-expr (car args) env)
           (gptel-sandbox--eval-sequential (cdr args) env))))
      ('unless
       (let ((args (cdr expr)))
         (unless (>= (length args) 1)
           (error "Programmatic unless requires at least 1 argument (condition), got: %d" (length args)))
         (unless (gptel-sandbox--eval-expr (car args) env)
           (gptel-sandbox--eval-sequential (cdr args) env))))
      ('progn
        (gptel-sandbox--eval-sequential (cdr expr) env))
      ('let
          (gptel-sandbox--eval-let (nth 1 expr) (cddr expr) env nil))
      ('let*
          (gptel-sandbox--eval-let (nth 1 expr) (cddr expr) env t))
      ('not
       (let ((args (cdr expr)))
         (unless (= (length args) 1)
           (error "Programmatic not requires exactly one argument, got: %d" (length args)))
         (not (gptel-sandbox--eval-expr (car args) env))))
      ('mapcar
       (gptel-sandbox--eval-map-like expr env nil))
      ('filter
       (gptel-sandbox--eval-map-like expr env t))
      ('and
       (gptel-sandbox--short-circuit-eval (cdr expr) env t #'not))
      ('or
       (gptel-sandbox--short-circuit-eval (cdr expr) env nil #'identity))
      ((or 'equal 'string= '= '< '> '<= '>=)
       (gptel-sandbox--apply-builtin (car expr) (cdr expr) env))
      ((or 'concat 'format 'list 'vector 'append 'length 'car 'cdr 'nth
           'cons 'assoc 'alist-get 'plist-get 'split-string 'string-join
           'string-trim 'string-empty-p 'string-match-p 'substring)
       (gptel-sandbox--apply-builtin (car expr) (cdr expr) env))
      ('tool-call
       (error "tool-call is only allowed as a top-level statement or setq RHS"))
      (_
       (error "Unsupported expression form in Programmatic sandbox: %S" (car expr)))))))

(defun gptel-sandbox--tool-arg-map (arg-pairs)
  "Convert ARG-PAIRS plist into a keyword->value hash table."
  (unless (listp arg-pairs)
    (error "Programmatic tool-call arguments must be a list, got: %S" arg-pairs))
  (let ((table (make-hash-table :test #'eq)))
    (while arg-pairs
      (let ((key (pop arg-pairs))
            (value (pop arg-pairs)))
        (unless (keywordp key)
          (error "Programmatic tool-call keys must be keywords, got: %S" key))
        (puthash key value table)))
    table))

(defun gptel-sandbox--resolve-tool-args (tool-spec arg-forms env)
  "Resolve TOOL-SPEC arguments from ARG-FORMS using ENV."
  (unless (cl-evenp (length arg-forms))
    (error "Programmatic tool-call requires keyword/value pairs"))
  (let* ((arg-map (gptel-sandbox--tool-arg-map arg-forms))
         (spec-args (gptel-tool-args tool-spec))
         (values nil))
    (dolist (arg spec-args (nreverse values))
      (let* ((name (plist-get arg :name))
             (key (intern (concat ":" name)))
             (value-form (gethash key arg-map gptel-sandbox--missing-marker)))
        (cond
         ((eq value-form gptel-sandbox--missing-marker)
          (if (plist-get arg :optional)
              (push nil values)
            (error "Missing required argument %s for tool %s"
                   name (gptel-tool-name tool-spec))))
         (t
          (push (gptel-sandbox--eval-expr value-form env) values)))))))

(defun gptel-sandbox--allowed-tool-p (tool-name)
  "Return non-nil when TOOL-NAME may run inside Programmatic."
  (let ((name-str (if (symbolp tool-name)
                      (symbol-name tool-name)
                    tool-name)))
    (member name-str
            (pcase (gptel-sandbox--current-profile)
              ('readonly my/gptel-programmatic-readonly-tools)
              (_ my/gptel-programmatic-allowed-tools)))))

(defun gptel-sandbox--confirm-supported-p (tool-name)
  "Return non-nil when TOOL-NAME may request confirmation in Programmatic."
  (let ((name-str (if (symbolp tool-name)
                      (symbol-name tool-name)
                    tool-name)))
    (and (eq (gptel-sandbox--current-profile) 'agent)
         (member name-str my/gptel-programmatic-confirming-tools))))

(defun gptel-sandbox--current-profile ()
  "Return the active Programmatic capability profile.
`readonly' is used for `gptel-plan`; `agent' is the default everywhere else."
  (or gptel-sandbox-profile
      (if (and (boundp 'gptel--preset)
               (eq gptel--preset 'gptel-plan))
          'readonly
        'agent)))

(defun gptel-sandbox--truncate-summary (value &optional width)
  "Return a compact printable summary of VALUE up to WIDTH chars."
  (let* ((width (or width 80))
         (text (prin1-to-string value)))
    (if (> (length text) width)
        (concat (substring text 0 width) "...")
      text)))

(defun gptel-sandbox--statement-tool-call (statement)
  "Return `(TOOL-NAME ARG-FORMS)' for top-level tool call STATEMENT, or nil."
  (pcase statement
    (`(setq ,_ (tool-call ,tool-name . ,arg-forms))
     (list tool-name arg-forms))
    (`(tool-call ,tool-name . ,arg-forms)
     (list tool-name arg-forms))
    (_ nil)))

(defun gptel-sandbox--summarize-tool-call-plan (tool-name arg-forms)
  "Build a human-readable summary for TOOL-NAME with ARG-FORMS."
  (let (parts)
    (while arg-forms
      (let ((key (pop arg-forms))
            (value (pop arg-forms)))
        (push (format "%s=%s"
                      (substring (symbol-name key) 1)
                      (gptel-sandbox--truncate-summary value 60))
              parts)))
    (list :tool-name tool-name
          :summary (if parts
                       (format "%s %s" tool-name (mapconcat #'identity (nreverse parts) " "))
                     tool-name))))

(defun gptel-sandbox--collect-confirming-plan (forms)
  "Collect static summaries for confirming tool calls in FORMS."
  (let (plan)
    (dolist (statement forms (nreverse plan))
      (pcase-let ((`(,tool-name ,arg-forms)
                   (or (gptel-sandbox--statement-tool-call statement)
                       '(nil nil))))
        (when (and tool-name
                   (let ((name (if (symbolp tool-name)
                                   (symbol-name tool-name)
                                 tool-name)))
                     (member name my/gptel-programmatic-confirming-tools)))
          (push (gptel-sandbox--summarize-tool-call-plan tool-name arg-forms)
                plan))))))

(defun gptel-sandbox--confirm-required-p (tool-spec arg-values)
  "Return non-nil when TOOL-SPEC with ARG-VALUES requires confirmation."
  (and (boundp 'gptel-confirm-tool-calls)
       gptel-confirm-tool-calls
       (or (eq gptel-confirm-tool-calls t)
           (and-let* ((confirm (gptel-tool-confirm tool-spec)))
             (or (not (functionp confirm))
                 (apply confirm arg-values))))))

(defun gptel-sandbox--default-confirm-tool (tool-spec arg-values callback)
  "Prompt for confirmation before nested TOOL-SPEC runs with ARG-VALUES.
CALLBACK receives non-nil when approved and nil when rejected."
  (let* ((tool-name (gptel-tool-name tool-spec))
         (formatted (if (fboundp 'gptel--format-tool-call)
                        (gptel--format-tool-call tool-name arg-values)
                      (format "%s %s" tool-name (mapconcat #'prin1-to-string arg-values " ")))))
    (if (and (fboundp 'my/gptel-tool-permitted-p)
             (ignore-errors (my/gptel-tool-permitted-p tool-name)))
        (funcall callback t)
      (funcall callback
               (y-or-n-p (format "Programmatic wants to run %s. Continue? " formatted))))))

(defun gptel-sandbox--default-aggregate-confirm (plan callback)
  "Prompt for confirmation before multi-step mutating Programmatic PLAN.
CALLBACK receives non-nil when approved and nil when rejected."
  (let ((summary (mapconcat (lambda (step)
                              (concat "- " (plist-get step :summary)))
                            plan "\n")))
    (funcall callback
             (y-or-n-p (format "Programmatic wants to run this mutating plan:\n%s\nApprove aggregate preview? "
                               summary)))))

(defun gptel-sandbox--maybe-aggregate-confirm (state callback)
  "Run aggregate mutating preview for STATE, then CALLBACK approval result."
  (let ((plan (plist-get state :mutating-plan)))
    (if (or (not (eq (gptel-sandbox--current-profile) 'agent))
            (plist-get state :aggregate-preview-shown)
            (null plan)
            (<= (length plan) 1))
        (funcall callback t)
      (funcall gptel-sandbox-aggregate-confirm-function
               plan
               (lambda (approved)
                 (when approved
                   (setf (plist-get state :aggregate-preview-shown) t))
                 (funcall callback approved))))))

(defun gptel-sandbox--check-tool (tool-spec arg-values)
  "Validate TOOL-SPEC with ARG-VALUES for sandbox execution."
  (unless tool-spec
    (error "Unknown tool requested by Programmatic"))
  (let ((tool-name (gptel-tool-name tool-spec)))
    (unless (gptel-sandbox--allowed-tool-p tool-name)
      (error "Tool %s is not allowed inside Programmatic %s mode"
             tool-name (gptel-sandbox--current-profile)))
    (when (string= tool-name "Programmatic")
      (error "Tool %s requires confirmation or recursion and is not supported inside Programmatic v1"
             tool-name))
    (when (and (gptel-sandbox--confirm-required-p tool-spec arg-values)
               (not (gptel-sandbox--confirm-supported-p tool-name)))
      (error "Tool %s requires confirmation and is not supported inside Programmatic %s mode"
             tool-name (gptel-sandbox--current-profile)))))

(defun gptel-sandbox--truncate-result (text)
  "Return TEXT, truncating and persisting to a temp file if needed."
  (let ((text (gptel-sandbox--render-result text)))
    (if (<= (length text) my/gptel-programmatic-result-limit)
        text
      (let* ((temp-file (if (fboundp 'my/gptel-make-temp-file)
                            (my/gptel-make-temp-file "programmatic-" nil ".txt")
                          (make-temp-file "programmatic-" nil ".txt")))
             (suffix (format "\n...[Programmatic result truncated. Full result saved to: %s]..."
                             temp-file))
             (suffix-len (length suffix))
             (limit my/gptel-programmatic-result-limit))
        (with-temp-file temp-file
          (insert text))
        (if (>= suffix-len limit)
            (format "%s" suffix)
          (let ((head-len (- limit suffix-len)))
            (format "%s%s" (substring text 0 (min head-len (length text))) suffix)))))))

(defun gptel-sandbox--format-error (message)
  "Format MESSAGE as a sandbox error string."
  (format "Error: %s" message))

(defun gptel-sandbox--wrap-result (result)
  "Wrap RESULT for callback, avoiding double-wrapping of error strings."
  (if (and (stringp result) (string-prefix-p "Error: " result))
      result
    (gptel-sandbox--format-result result)))

(defun gptel-sandbox--format-result (result)
  "Convert RESULT to string, preferring gptel--to-string when available."
  (if (fboundp 'gptel--to-string)
      (gptel--to-string result)
    (format "%s" result)))

(defun gptel-sandbox--render-result (value)
  "Render VALUE into the final string returned by Programmatic.
Strings are returned directly. Structured values are pretty-printed so the LLM
can consume lists, vectors, plists, and alists as readable data."
  (cond
   ((stringp value) value)
   ((null value) "nil")
   ((or (numberp value) (keywordp value) (symbolp value))
    (format "%s" value))
   (t
    (string-trim-right
     (let ((print-length nil)
           (print-level nil)
           (print-circle t))
       (pp-to-string value))))))

(defun gptel-sandbox--execute-tool (callback tool-name arg-forms env state)
  "Execute TOOL-NAME with ARG-FORMS in ENV and STATE, then CALLBACK the result."
  (let* ((tool-spec (if (fboundp 'gptel-get-tool)
                        (gptel-get-tool tool-name)
                      nil))
         (arg-values (and tool-spec
                          (gptel-sandbox--resolve-tool-args tool-spec arg-forms env))))
    (gptel-sandbox--check-tool tool-spec arg-values)
    (cl-incf (plist-get state :tool-count))
    (when (> (plist-get state :tool-count) my/gptel-programmatic-max-tool-calls)
      (error "Programmatic exceeded max nested tool calls (%d)"
             my/gptel-programmatic-max-tool-calls))
    (condition-case err
        (let ((invoke-tool
               (lambda ()
                 (if (gptel-tool-async tool-spec)
                     (apply (gptel-tool-function tool-spec)
                            (lambda (result)
                              (condition-case cb-err
                                  (funcall callback (gptel-sandbox--wrap-result result))
                                (error (funcall callback
                                                (gptel-sandbox--wrap-result
                                                 (gptel-sandbox--format-error
                                                  (error-message-string cb-err)))))))
                            arg-values)
                   (let ((result (condition-case inner-err
                                     (apply (gptel-tool-function tool-spec) arg-values)
                                   (error (gptel-sandbox--format-error (error-message-string inner-err))))))
                     (funcall callback (gptel-sandbox--wrap-result result)))))))
          (if (gptel-sandbox--confirm-required-p tool-spec arg-values)
              (gptel-sandbox--maybe-aggregate-confirm
               state
               (lambda (aggregate-approved)
                 (if aggregate-approved
                     (funcall gptel-sandbox-confirm-function
                              tool-spec arg-values
                              (lambda (approved)
                                (if approved
                                    (funcall invoke-tool)
                                  (funcall callback
                                           (gptel-sandbox--format-error
                                            (format "Programmatic tool call rejected by user: %s"
                                                    (gptel-tool-name tool-spec)))))))
                   (funcall callback
                            "Error: Programmatic aggregate preview rejected by user"))))
            (funcall invoke-tool)))
      (error
       (funcall callback (gptel-sandbox--format-error (error-message-string err)))))))

(defun gptel-sandbox--eval-statement (statement env state callback)
  "Evaluate sandbox STATEMENT with ENV and STATE, then CALLBACK.
CALLBACK receives a plist with one of the keys `:continue' or `:result'."
  (pcase statement
    (`(progn . ,body)
     (gptel-sandbox--eval-progn body env state callback))
    (`(setq . ,pairs)
     (if (null pairs)
         (funcall callback (list :continue t :done nil))
       (let ((remaining (gptel-sandbox--validate-setq-pairs pairs)))
         (cl-labels
             ((process-pair
                ()
                (if (null remaining)
                    (funcall callback (list :continue t :done nil))
                  (let* ((entry (car remaining))
                         (symbol (car entry))
                         (expr (cdr entry)))
                    (if (and (consp expr) (eq (car expr) 'tool-call))
                        (gptel-sandbox--execute-tool
                         (lambda (value)
                           (if (string-prefix-p "Error: " value)
                               (funcall callback (list :done t :result value))
                             (gptel-sandbox--bind-result symbol value env)
                             (setq remaining (cdr remaining))
                             (process-pair)))
                         (nth 1 expr) (cddr expr) env state)
                      (let ((value (gptel-sandbox--eval-expr expr env)))
                        (gptel-sandbox--bind-result symbol value env)
                        (setq remaining (cdr remaining))
                        (process-pair)))))))
           (process-pair)))))
    (`(tool-call ,tool-name . ,arg-forms)
     (gptel-sandbox--execute-tool
      (lambda (value)
        (if (string-prefix-p "Error: " value)
            (funcall callback (list :done t :result value))
          (gptel-sandbox--bind-last-value value env)
          (funcall callback (list :continue t :done nil))))
      tool-name arg-forms env state))
    (`(result ,expr)
     (funcall callback (list :done t :result (gptel-sandbox--eval-expr expr env))))
    (_
     (error "Unsupported statement in Programmatic sandbox: %S"
            (if (consp statement) (car statement) statement)))))

(defun gptel-sandbox--eval-progn (body env state callback)
  "Evaluate BODY forms sequentially, handling async tool-calls.
CALLBACK receives final outcome plist."
  (if (null body)
      (funcall callback (list :continue t :done nil))
    (gptel-sandbox--eval-statement
     (car body) env state
     (lambda (outcome)
       (if (plist-get outcome :done)
           (funcall callback outcome)
         (gptel-sandbox--eval-progn (cdr body) env state callback))))))

(defun gptel-sandbox--run-forms (forms env state callback)
  "Run sandbox FORMS with ENV and STATE, then CALLBACK final result."
  (if (null forms)
      (funcall callback "Error: Programmatic execution finished without calling result")
    (gptel-sandbox--eval-statement
     (car forms) env state
     (lambda (outcome)
       (if (plist-get outcome :done)
           (funcall callback (gptel-sandbox--truncate-result
                              (plist-get outcome :result)))
         (gptel-sandbox--run-forms (cdr forms) env state callback))))))

;;; Public API

(defun gptel-sandbox-execute-async (callback code &optional profile)
  "Execute restricted Programmatic CODE and call CALLBACK with the result.
PROFILE is either `agent' or `readonly'."
  (let ((done nil)
        (timer nil)
        (env (gptel-sandbox--make-env))
        (gptel-sandbox-profile (or profile gptel-sandbox-profile)))
    (cl-labels
        ((finish (result)
           (unless done
             (setq done t)
             (when (timerp timer)
               (cancel-timer timer))
             (funcall callback result))))
      (condition-case err
          (progn
            (unless (and (stringp code) (not (string-empty-p (string-trim code))))
              (error "Programmatic code is empty"))
            (let* ((forms (gptel-sandbox--parse-forms code))
                   (state (list :tool-count 0
                                :mutating-plan (gptel-sandbox--collect-confirming-plan forms)
                                :aggregate-preview-shown nil)))
              (setq timer
                    (run-at-time
                     my/gptel-programmatic-timeout nil
                     (lambda ()
                       (finish
                        (format "Error: Programmatic timed out after %ss"
                                my/gptel-programmatic-timeout)))))
              (gptel-sandbox--run-forms forms env state #'finish)))
        (error
         (finish (gptel-sandbox--format-error (error-message-string err))))))))

(provide 'gptel-sandbox)

;;; gptel-sandbox.el ends here
