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
(require 'nucleus-tools)

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

(defconst gptel-sandbox--excluded-tools
  (append (nucleus-tools-with-marker :sandbox-excluded)
          (nucleus-tools-with-marker :delegates))
  "Tools excluded from all sandbox profiles regardless of markers.
Derived from :sandbox-excluded and :delegates markers.
These tools escape the sandbox, don't make sense in Programmatic context,
or require user interaction that can't be handled inside sandbox execution.")

(defun gptel-sandbox--default-allowed-tools ()
  "Compute default allowed tools for Programmatic agent profile from markers.
Includes read+edit tools, excludes delegates, web, and sandbox-external tools."
  (seq-difference
   (nucleus-tools-with-any-marker :can-read :can-edit)
   (append (nucleus-tools-with-any-marker :delegates :web)
           gptel-sandbox--excluded-tools)
   #'equal))

(defun gptel-sandbox--default-readonly-tools ()
  "Compute default readonly tools for Programmatic readonly profile from markers."
  (seq-difference
   (nucleus-toolset-from-markers '(:can-read) '(:can-edit :plan-excluded :web))
   gptel-sandbox--excluded-tools
   #'equal))

(defun gptel-sandbox--default-confirming-tools ()
  "Compute default confirming tools from markers."
  (nucleus-toolset-from-markers '(:can-edit) '(:delegates)))

(defun gptel-sandbox--load-profile-from-skill (profile-name)
  "Load tool profile PROFILE-NAME from sandbox-profiles skill.
Returns list of tool names or nil if skill not found."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let* ((skill (gptel-auto-workflow--load-skill-content "sandbox-profiles"))
           (profile-regexp (format "### %s\\n.*?```json\\n\\(.*?\\)\\n```"
                                   (regexp-quote profile-name))))
      (when (and skill (string-match profile-regexp skill))
        (let ((json-str (match-string 1 skill)))
          (condition-case nil
              (let ((profile (json-read-from-string json-str)))
                (cdr (assq 'allowed profile)))
            (error nil)))))))

(defcustom my/gptel-programmatic-allowed-tools
  (or (gptel-sandbox--load-profile-from-skill "emacs-lisp")
      (gptel-sandbox--default-allowed-tools))
  "Tool names allowed inside Programmatic execution.
Loaded from sandbox-profiles skill if available, otherwise derived from
`nucleus-tool-markers' (all read+edit tools minus delegates, web, and
sandbox-external tools)."
  :type '(repeat string)
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-readonly-tools
  (or (gptel-sandbox--load-profile-from-skill "readonly-audit")
      (gptel-sandbox--default-readonly-tools))
  "Tool names allowed inside Programmatic when running in readonly mode.
Loaded from sandbox-profiles skill if available, otherwise derived from
`nucleus-tool-markers' (can-read minus can-edit, plan-excluded, web,
and sandbox-external tools)."
  :type '(repeat string)
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-confirming-tools
  (gptel-sandbox--default-confirming-tools)
  "Tool names allowed to request confirmation inside Programmatic.
Derived from `nucleus-tool-markers' (can-edit tools minus delegates).
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

;;; Sandbox Operation Constants

(defconst gptel-sandbox--comparison-ops
  '(equal string= eq = < > <= >=)
  "Comparison operators allowed in sandbox expressions.")

(defconst gptel-sandbox--data-ops
  '(+ - * / 1+ 1- mod max min abs minusp
    concat format list vector append length car cdr nth
    cons assoc alist-get plist-get split-string string-join
    string-trim string-empty-p string-match-p substring
    memq)
  "Data and arithmetic operators allowed in sandbox expressions.")

(defconst gptel-sandbox--builtin-ops
  (append gptel-sandbox--comparison-ops gptel-sandbox--data-ops)
  "All built-in operators available in sandbox expressions.")

(defconst gptel-sandbox--builtin-arity
  '((length 1 1) (car 1 1) (cdr 1 1) (nth 2 2) (cons 2 2)
    (assoc 2 3) (plist-get 2 3) (string-empty-p 1 1)
    (string-match-p 2 3) (format 1 nil) (split-string 1 4)
    (string-join 1 2) (string-trim 1 3) (substring 2 3)
    (memq 2 2)
    (alist-get 2 5)
    (+ 0 nil) (- 1 nil) (* 0 nil) (/ 1 nil)
    (1+ 1 1) (1- 1 1) (mod 2 2) (max 1 nil) (min 1 nil) (abs 1 1)
    (minusp 1 1)
    (equal 2 nil) (string= 2 nil) (eq 2 nil) (= 2 nil)
    (< 1 nil) (> 1 nil) (<= 1 nil) (>= 1 nil))
  "Alist of (FUNC MIN-ARGS MAX-ARGS) for arity validation.
MAX-ARGS of nil means no upper bound.")
;;; Internal Helpers

(defvar gptel-sandbox--missing-marker (make-symbol "gptel-sandbox-missing")
  "Sentinel value for detecting missing symbol lookups in sandbox env.")

(defvar gptel-sandbox--whitespace-comment-regexp
  (concat "\\`[ \t\n\r]*\\(?:;[^\n]*\n?[ \t\n\r]*\\)*\\'")
  "Pre-compiled regex matching whitespace and line comments.
Used in `gptel-sandbox--parse-forms' to detect trailing garbage.")

(defun gptel-sandbox--parse-forms (code)
  "Parse CODE into a list of Lisp forms."
  (unless (stringp code)
    (error "Programmatic parse-forms requires a string, got: %S" code))
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
         (if (string-match-p gptel-sandbox--whitespace-comment-regexp
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
  (unless (hash-table-p env)
    (error "Programmatic sandbox copy-env requires a hash table environment, got: %S" env))
  (let ((copy (make-hash-table :test #'eq)))
    (cl-flet ((copy-binding (key value)
               (puthash key value copy)))
      (maphash #'copy-binding env))
    copy))

(defun gptel-sandbox--bind-result (symbol value env)
  "Bind SYMBOL to VALUE in ENV, also updating `_` and `it`."
  (unless (hash-table-p env)
    (error "Programmatic sandbox bind-result requires a hash table environment, got: %S" env))
  (unless (symbolp symbol)
    (error "Binding target must be a symbol, got: %S" symbol))
  (when (null symbol)
    (error "Binding target cannot be nil"))
  (puthash symbol value env)
  (puthash '_ value env)
  (puthash 'it value env))

(defun gptel-sandbox--bind-last-value (value env)
  "Bind VALUE to last-result placeholders `_` and `it` in ENV."
  (unless (hash-table-p env)
    (error "Programmatic sandbox bind-last-value requires a hash table environment, got: %S" env))
  (puthash '_ value env)
  (puthash 'it value env))

(defun gptel-sandbox--normalize-binding (binding)
  "Normalize a let-style BINDING into `(SYMBOL VALUE-FORM)'."
  (cond
   ((null binding)
    (error "Programmatic let binding cannot be nil"))
   ((symbolp binding)
    (list binding nil))
   ((proper-list-p binding)
    (unless (symbolp (car binding))
      (error "Programmatic let binding car must be a symbol, got: %S" binding))
    (unless (<= (length binding) 2)
      (error "Programmatic let binding must have at most 2 elements, got: %S" binding))
    (list (car binding) (cadr binding)))
   (t
    (error "Programmatic let binding must be a proper list, got: %S" binding))))

(defun gptel-sandbox--validate-setq-pairs (pairs)
  "Validate PAIRS as symbol/value pairs, returning (SYMBOL . VALUE-FORM) entries.
Raises an error if PAIRS is malformed."
  (unless (proper-list-p pairs)
    (error "Programmatic setq requires a proper list of pairs, got: %S" pairs))
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
  (let ((normalized (gptel-sandbox--normalize-binding binding)))
    (unless (proper-list-p normalized)
      (error "Programmatic let binding normalized to non-proper-list: %S" normalized))
    (pcase-let ((`(,symbol ,value-form) normalized))
      (cons symbol (gptel-sandbox--eval-expr value-form env)))))

(defun gptel-sandbox--eval-let (bindings body env sequentialp)
  "Evaluate let-style BINDINGS and BODY in ENV.
When SEQUENTIALP is non-nil, evaluate bindings sequentially like `let*'."
  (unless (proper-list-p bindings)
    (error "Programmatic let bindings must be a proper list, got: %S" bindings))
  (unless (proper-list-p body)
    (error "Programmatic let body must be a proper list, got: %S" body))
  (let ((child-env (gptel-sandbox--copy-env env)))
    (if sequentialp
        (dolist (binding bindings)
          (when (null binding)
            (error "Programmatic let binding cannot be nil"))
          (pcase-let ((`(,symbol . ,value)
                       (gptel-sandbox--eval-let-binding binding child-env)))
            (gptel-sandbox--bind-result symbol value child-env)))
      (dolist (binding bindings)
        (when (null binding)
          (error "Programmatic let binding cannot be nil"))
        (pcase-let ((`(,symbol . ,value)
                     (gptel-sandbox--eval-let-binding binding env)))
          (gptel-sandbox--bind-result symbol value child-env))))
    (let ((value nil))
      (dolist (form body value)
        (setq value (gptel-sandbox--eval-expr form child-env))))))

(defcustom my/gptel-programmatic-max-loop-iterations 100
  "Maximum iterations allowed in dolist/while loops.
Prevents runaway loops consuming CPU. Matches context-mode's iteration guard pattern."
  :type 'integer
  :group 'gptel-sandbox)

(defun gptel-sandbox--eval-dolist (expr env)
  "Evaluate sandbox dolist EXPR in ENV with iteration guard.
Shape: (dolist (item list [result]) body...)
Max iterations bounded by my/gptel-programmatic-max-loop-iterations."
  (pcase expr
    (`(,_ (,item ,list-expr . ,result-form) . ,body)
     (unless (symbolp item)
       (error "Programmatic dolist variable must be a symbol, got: %S" item))
     (let* ((items (gptel-sandbox--eval-expr list-expr env))
            (result-var (car result-form))
            (iterations 0)
            (max-iter my/gptel-programmatic-max-loop-iterations))
       (unless (proper-list-p items)
         (error "Programmatic dolist expects a proper list, got: %S" items))
       (let ((child-env (gptel-sandbox--copy-env env))
             (value nil))
         (catch 'dolist-done
           (dolist (item-val items value)
             (when (>= (cl-incf iterations) max-iter)
               (throw 'dolist-done
                      (format "[dolist truncated at %d iterations]" max-iter)))
             (puthash item item-val child-env)
             (dolist (form body)
               (setq value (gptel-sandbox--eval-expr form child-env)))))
         (when result-var
           (puthash result-var value child-env)
           (gptel-sandbox--eval-expr result-var child-env)))))
    (_
     (error "Programmatic dolist requires (var list [result]) and body forms"))))

(defun gptel-sandbox--eval-map-like (expr env filterp)
  "Evaluate sandbox `mapcar' or `filter' EXPR in ENV.
When FILTERP is non-nil, keep original items whose body is truthy;
otherwise collect each mapped result.

Supported shape:
  (mapcar (lambda (item) BODY...) LIST)
  (filter (lambda (item) BODY...) LIST)"
  ;; ASSUMPTION: list-expr must evaluate to a proper list for safe iteration
  ;; BEHAVIOR: Maps or filters items using an isolated child env per iteration
  ;; EDGE CASE: Rejects improper/dotted lists that would cause dolist errors
  ;; TEST: Pass a dotted list as input and verify error is raised
  (let ((op-name (if filterp "filter" "mapcar")))
    (pcase expr
      (`(,_ (lambda (,arg) . ,body) ,list-expr)
       (unless (symbolp arg)
         (error "Programmatic %s lambda arg must be a symbol" op-name))
       (let ((items (gptel-sandbox--eval-expr list-expr env))
             (results nil))
         (unless (proper-list-p items)
           (error "Programmatic %s expects a proper list input, got: %S" op-name items))
         (dolist (item items (nreverse results))
           ;; Each lambda invocation needs an isolated child env so `setq'
           ;; state does not leak between map/filter iterations.
           (let ((child-env (gptel-sandbox--copy-env env)))
             (puthash arg item child-env)
             (let ((value nil))
               (dolist (form body)
                 (setq value (gptel-sandbox--eval-expr form child-env)))
               (if filterp
                   (when value
                     (push item results))
                 (push value results)))))))
      (_
       (error "Programmatic %s requires (lambda (item) ...) and a list" op-name)))))

(defun gptel-sandbox--lookup (symbol env)
  "Look up SYMBOL in ENV or signal an error."
  (unless (hash-table-p env)
    (error "Programmatic sandbox lookup requires a hash table environment, got: %S" env))
  (unless (symbolp symbol)
    (error "Programmatic sandbox lookup requires a symbol, got: %S" symbol))
  (let ((value (gethash symbol env gptel-sandbox--missing-marker)))
    (if (eq value gptel-sandbox--missing-marker)
        (error "Unknown symbol in Programmatic sandbox: %S" symbol)
      value)))

(defun gptel-sandbox--eval-sequential (forms env)
  "Evaluate FORMS sequentially in ENV, returning the last result."
  (unless (proper-list-p forms)
    (error "Programmatic eval-sequential requires a proper list, got: %S" forms))
  (let ((value nil))
    (dolist (form forms value)
      (setq value (gptel-sandbox--eval-expr form env)))))

(defun gptel-sandbox--short-circuit-eval (forms env initial-value stop-pred)
  "Evaluate FORMS sequentially with short-circuit logic.
INITIAL-VALUE is the starting value. STOP-PRED is called on each result;
when non-nil, evaluation short-circuits and returns that result.
Used by `and' and `or' to share short-circuit evaluation logic."
  ;; ASSUMPTION: forms must be a proper list for safe dolist iteration
  ;; BEHAVIOR: Evaluates forms left-to-right, stopping when stop-pred matches
  ;; EDGE CASE: Rejects improper/dotted lists that would cause dolist errors
  ;; TEST: Pass a dotted list like '(t . nil) and verify error is raised
  (unless (proper-list-p forms)
    (error "Programmatic short-circuit requires a proper list of forms, got: %S" forms))
  (unless (functionp stop-pred)
    (error "Programmatic short-circuit requires a function predicate, got: %S" stop-pred))
  (let ((value initial-value))
    (catch 'gptel-sandbox-short-circuit
      (dolist (form forms value)
        (setq value (gptel-sandbox--eval-expr form env))
        (when (funcall stop-pred value)
          (throw 'gptel-sandbox-short-circuit value))))))

(defun gptel-sandbox--apply-builtin (func args env)
  "Apply built-in function FUNC to evaluated ARGS in ENV.
Errors propagate to the outer condition-case in `execute-tool'."
  ;; ASSUMPTION: args must be a proper list for safe mapcar evaluation
  ;; BEHAVIOR: Validates args, evaluates each, checks arity, applies func
  ;; EDGE CASE: Rejects dotted lists that would cause silent truncation
  ;; TEST: Pass a dotted list like '(a b . c) and verify error is raised
  (unless (functionp func)
    (error "Programmatic builtin requires a function, got: %S" func))
  (unless (proper-list-p args)
    (error "Programmatic builtin arguments must be a proper list, got: %S" args))
  (let ((evaluated (mapcar (lambda (arg) (gptel-sandbox--eval-expr arg env)) args))
        (arity (assq func gptel-sandbox--builtin-arity)))
    (when arity
      (let* ((min-args (nth 1 arity))
             (max-args (nth 2 arity))
             (n (length evaluated)))
        (when (< n min-args)
          (error "Programmatic `%s` requires at least %d argument%s, got %d"
                 func min-args (if (= min-args 1) "" "s") n))
        (when (and max-args (> n max-args))
          (error "Programmatic `%s` requires at most %d argument%s, got %d"
                 func max-args (if (= max-args 1) "" "s") n))))
    (apply func evaluated)))

(defun gptel-sandbox--eval-expr (expr env)
  "Evaluate pure sandbox expression EXPR in ENV.
This evaluator intentionally excludes general function application and only
supports a small, explicit whitelist of pure operations."
  (unless (hash-table-p env)
    (error "Programmatic eval-expr requires a hash table environment, got: %S" env))
  (cond
   ((or (stringp expr) (numberp expr) (keywordp expr) (vectorp expr)) expr)
   ((memq expr '(t nil)) expr)
   ((symbolp expr) (gptel-sandbox--lookup expr env))
   ((not (consp expr)) expr)
   (t
    (pcase (car expr)
      ('quote
       (let ((args (cdr expr)))
         (unless (= (length args) 1)
           (error "Programmatic quote requires exactly one argument, got: %d" (length args)))
         (cadr expr)))
      ('if
          (let ((args (cdr expr)))
            (unless (>= (length args) 2)
              (error "Programmatic if requires at least 2 arguments (condition and then-form), got:
%d" (length args)))
            (let ((cond-result (gptel-sandbox--eval-expr (car args) env)))
              (if cond-result
                  (gptel-sandbox--eval-expr (cadr args) env)
                (gptel-sandbox--eval-sequential (cddr args) env)))))
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
      ('dolist
       (gptel-sandbox--eval-dolist expr env))
      ('and
       (gptel-sandbox--short-circuit-eval (cdr expr) env t #'not))
      ('or
       (gptel-sandbox--short-circuit-eval (cdr expr) env nil #'identity))
      ((guard (memq (car expr) gptel-sandbox--comparison-ops))
       (gptel-sandbox--apply-builtin (car expr) (cdr expr) env))
      ((guard (memq (car expr) gptel-sandbox--data-ops))
       (gptel-sandbox--apply-builtin (car expr) (cdr expr) env))
      ('tool-call
       (error "tool-call is only allowed as a top-level statement or setq RHS"))
      (_
       (error "Unsupported expression form in Programmatic sandbox: %S" (car expr)))))))

(defun gptel-sandbox--tool-arg-map (arg-pairs)
  "Convert ARG-PAIRS plist into a keyword->value hash table."
  (unless (proper-list-p arg-pairs)
    (error "Programmatic tool-call arguments must be a proper list, got: %S" arg-pairs))
  (unless (cl-evenp (length arg-pairs))
    (error "Programmatic tool-call requires keyword/value pairs, got odd length: %d"
           (length arg-pairs)))
  (let ((table (make-hash-table :test #'eq)))
    (while arg-pairs
        (let ((key (pop arg-pairs))
              (value (pop arg-pairs)))
        (unless (keywordp key)
          (error "Programmatic tool-call keys must be keywords, got: %S" key))
        (puthash key value table)))
    table))

(defun gptel-sandbox--tool-slot (tool-spec accessor slot-name)
  "Return TOOL-SPEC slot SLOT-NAME using ACCESSOR or a struct fallback."
  (let ((value (condition-case nil
                   (funcall accessor tool-spec)
                 (error gptel-sandbox--missing-marker))))
    (if (not (eq value gptel-sandbox--missing-marker))
        value
      (let* ((type (and tool-spec (type-of tool-spec)))
             (fallback (and (symbolp type)
                            (intern-soft (format "%s-%s" type slot-name)))))
        (cond
         ((and fallback (fboundp fallback))
          (funcall fallback tool-spec))
         ((proper-list-p tool-spec)
          (plist-get tool-spec (intern (format ":%s" slot-name))))
         (t
          (error "Programmatic tool spec is missing gptel-tool accessors, got: %S"
                 tool-spec)))))))

(defun gptel-sandbox--resolve-tool-args (tool-spec arg-forms env)
  "Resolve TOOL-SPEC arguments from ARG-FORMS using ENV."
  (unless (proper-list-p arg-forms)
    (error "Programmatic tool-call arguments must be a proper list, got: %S" arg-forms))
  (unless (cl-evenp (length arg-forms))
    (error "Programmatic tool-call requires keyword/value pairs"))
  (unless (and tool-spec (fboundp 'gptel-tool-args))
    (error "Programmatic tool spec is missing gptel-tool accessors, got: %S" tool-spec))
  (let* ((arg-map (gptel-sandbox--tool-arg-map arg-forms))
         (spec-args (gptel-sandbox--tool-slot tool-spec #'gptel-tool-args "args")))
    (unless (proper-list-p spec-args)
      (error "Programmatic tool spec returned invalid :args property (must be proper list), got: %S" spec-args))
    (let ((values nil))
      (dolist (arg spec-args (nreverse values))
        (unless (proper-list-p arg)
          (error "Programmatic tool spec returned invalid argument (must be proper list), got: %S" arg))
        (let* ((name (plist-get arg :name))
               (key (and (stringp name) (intern (concat ":" name))))
               (key-present (and key (not (eq (gethash key arg-map gptel-sandbox--missing-marker)
                                              gptel-sandbox--missing-marker)))))
          (cond
           ((not key)
            (error "Invalid tool spec: argument missing :name property"))
           ((not key-present)
            (if (plist-get arg :optional)
                (push nil values)
               (error "Missing required argument %s for tool %s"
                      name (gptel-sandbox--tool-slot tool-spec #'gptel-tool-name "name"))))
           (t
             (let ((raw-value (gethash key arg-map)))
               (push (if (null raw-value)
                         nil
                       (gptel-sandbox--eval-expr raw-value env))
                      values)))))))))

(defun gptel-sandbox--normalize-tool-name (tool-name)
  "Convert TOOL-NAME to string representation.
Signals an error if TOOL-NAME is nil or neither a symbol nor string."
  (unless tool-name
    (error "Programmatic tool name cannot be nil"))
  (unless (or (symbolp tool-name) (stringp tool-name))
    (error "Programmatic tool name must be a symbol or string, got: %S" tool-name))
  (if (symbolp tool-name)
      (symbol-name tool-name)
    tool-name))

(defun gptel-sandbox--allowed-tool-p (tool-name)
  "Return non-nil when TOOL-NAME may run inside Programmatic."
  (let ((name-str (gptel-sandbox--normalize-tool-name tool-name)))
    (member name-str
            (pcase (gptel-sandbox--current-profile)
              ('readonly (if (boundp 'my/gptel-programmatic-readonly-tools)
                             my/gptel-programmatic-readonly-tools
                           my/gptel-programmatic-allowed-tools))
              (_ my/gptel-programmatic-allowed-tools)))))

(defun gptel-sandbox--confirm-supported-p (tool-name)
  "Return non-nil when TOOL-NAME may request confirmation in Programmatic."
  (let ((name-str (gptel-sandbox--normalize-tool-name tool-name)))
    (and (eq (gptel-sandbox--current-profile) 'agent)
         (boundp 'my/gptel-programmatic-confirming-tools)
         (member name-str my/gptel-programmatic-confirming-tools))))

(defun gptel-sandbox--current-profile ()
  "Return the active Programmatic capability profile.
Uses marker availability when possible: if no :can-edit tools are active,
returns `readonly'. Falls back to preset check, then `agent'."
  (or gptel-sandbox-profile
      (cond
       ((and (boundp 'gptel--preset)
             (eq gptel--preset 'gptel-plan))
        'readonly)
       ((and (fboundp 'nucleus-marker-available-p)
             (not (nucleus-marker-available-p :can-edit)))
        'readonly)
       (t 'agent))))

(defun gptel-sandbox--truncate-summary (value &optional width)
  "Return a compact printable summary of VALUE up to WIDTH chars."
  (let* ((width (if (and (integerp width) (>= width 1)) width 80))
         (text (condition-case err
                   (prin1-to-string value)
                 (error
                  (format "[unprintable: %s]" (error-message-string err))))))
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
  (when (null tool-name)
    (error "Programmatic summarize-tool-call-plan requires a non-nil tool-name, got: nil"))
  (unless (proper-list-p arg-forms)
    (error "Programmatic tool-call requires a proper list of arguments, got: %S" arg-forms))
  (unless (cl-evenp (length arg-forms))
    (error "Programmatic tool-call requires keyword/value pairs, got odd length: %d"
           (length arg-forms)))
  (let (parts)
    (while arg-forms
      (let ((key (pop arg-forms))
            (value (pop arg-forms)))
        (let ((key-str (cond
                        ((keywordp key) (substring (symbol-name key) 1))
                        ((symbolp key) (symbol-name key))
                        (t (format "%s" key)))))
          (push (format "%s=%s"
                        key-str
                        (gptel-sandbox--truncate-summary value 60))
                parts))))
    (list :tool-name tool-name
          :summary (if parts
                       (format "%s %s" tool-name (mapconcat #'identity (nreverse parts) " "))
                     tool-name))))

(defun gptel-sandbox--collect-confirming-plan (forms)
  "Collect static summaries for confirming tool calls in FORMS."
  (unless (proper-list-p forms)
    (error "Programmatic collect-confirming-plan requires a proper list, got: %S" forms))
  (let (plan)
    (dolist (statement forms (nreverse plan))
      (pcase-let ((`(,tool-name ,arg-forms)
                   (or (gptel-sandbox--statement-tool-call statement)
                       '(nil nil))))
        (when (and tool-name
                   (boundp 'my/gptel-programmatic-confirming-tools)
                   (let ((name (gptel-sandbox--normalize-tool-name tool-name)))
                     (member name my/gptel-programmatic-confirming-tools)))
          (push (gptel-sandbox--summarize-tool-call-plan tool-name arg-forms)
                plan))))))

(defun gptel-sandbox--confirm-required-p (tool-spec arg-values)
  "Return non-nil when TOOL-SPEC with ARG-VALUES requires confirmation."
  (unless (proper-list-p tool-spec)
    (error "Programmatic confirm-required-p requires a proper plist tool-spec, got: %S" tool-spec))
  (unless (proper-list-p arg-values)
    (error "Programmatic confirm-required-p requires a proper list arg-values, got: %S" arg-values))
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
             (condition-case nil
                 (prog1 (my/gptel-tool-permitted-p tool-name)
                   t)
               (error nil)))
        (funcall callback t)
      (funcall callback
               (y-or-n-p (format "Programmatic wants to run %s. Continue? " formatted))))))

(defun gptel-sandbox--default-aggregate-confirm (plan callback)
  "Prompt for confirmation before multi-step mutating Programmatic PLAN.
CALLBACK receives non-nil when approved and nil when rejected."
  (unless (proper-list-p plan)
    (error "Programmatic aggregate-confirm requires a proper list plan, got: %S" plan))
  (let ((summary (mapconcat (lambda (step)
                              (unless (proper-list-p step)
                                (error "Programmatic aggregate-confirm requires proper plist steps, got: %S" step))
                              (let ((step-summary (plist-get step :summary)))
                                (if (and step-summary (stringp step-summary) (not (string-empty-p step-summary)))
                                    (concat "- " step-summary)
                                  (let ((tool-name (plist-get step :tool-name)))
                                    (if tool-name
                                        (format "- %s" tool-name)
                                      "- <unnamed step>")))))
                            plan "\n")))
    (funcall callback
             (y-or-n-p (format "Programmatic wants to run this mutating plan:\n%s\nApprove aggregate preview? "
                               summary)))))

(defun gptel-sandbox--maybe-aggregate-confirm (state callback)
  "Run aggregate mutating preview for STATE, then CALLBACK approval result."
  (unless (proper-list-p state)
    (error "Programmatic maybe-aggregate-confirm requires a proper plist state, got: %S" state))
  (let ((plan (plist-get state :mutating-plan)))
    (unless (or (null plan) (proper-list-p plan))
      (error "Programmatic aggregate-confirm plan must be a proper list, got: %S" plan))
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

(defun gptel-sandbox--check-tool (tool-name tool-spec arg-values)
  "Validate TOOL-NAME and TOOL-SPEC with ARG-VALUES for sandbox execution."
  (unless tool-name
    (error "Tool name cannot be nil"))
  (unless (or (symbolp tool-name) (stringp tool-name))
    (error "Tool name must be a symbol or string, got: %S" tool-name))
  (unless tool-spec
    (error "Unknown tool %s requested by Programmatic" tool-name))
  (unless (gptel-sandbox--allowed-tool-p tool-name)
    (error "Tool %s is not allowed inside Programmatic %s mode"
           tool-name (gptel-sandbox--current-profile)))
  (let ((tool-name-str (gptel-sandbox--normalize-tool-name tool-name)))
    (when (string= tool-name-str "Programmatic")
      (error "Tool %s requires confirmation or recursion and is not supported inside Programmatic v1"
             tool-name)))
  (when (and (gptel-sandbox--confirm-required-p tool-spec arg-values)
             (not (gptel-sandbox--confirm-supported-p tool-name)))
    (error "Tool %s requires confirmation and is not supported inside Programmatic %s mode"
           tool-name (gptel-sandbox--current-profile))))

(defun gptel-sandbox--truncate-result (text)
  "Return TEXT, truncating and persisting to a temp file if needed."
  (let ((text (gptel-sandbox--render-result text))
        (limit my/gptel-programmatic-result-limit))
    (if (<= (length text) limit)
        text
      (when (<= limit 0)
        (error "Programmatic result-limit must be positive, got: %S" limit))
      (let* ((temp-file (if (fboundp 'my/gptel-make-temp-file)
                            (my/gptel-make-temp-file "programmatic-" nil ".txt")
                          (make-temp-file "programmatic-" nil ".txt")))
             (suffix (format "\n...[Programmatic result truncated. Full result saved to: %s]..."
                             temp-file))
             (suffix-len (length suffix)))
        (with-temp-file temp-file
          (insert text))
        (if (>= suffix-len limit)
            (format "%s" suffix)
          (let ((head-len (- limit suffix-len)))
            (format "%s%s" (substring text 0 (min head-len (length text))) suffix)))))))

(defun gptel-sandbox--format-error (message)
  "Format MESSAGE as a sandbox error string."
  (condition-case err
      (format "Error: %s" (if (stringp message) message (format "%S" message)))
    (error
     (format "Error: %s" (error-message-string err)))))

(defun gptel-sandbox--error-plist-p (plist)
  "Return non-nil if PLIST is an error plist with :error, :violated, or :reason
keys."
  (and (proper-list-p plist)
       (or (plist-member plist :error)
           (plist-member plist :violated)
           (plist-member plist :reason))))

(defun gptel-sandbox--error-result-p (value)
  "Return non-nil if VALUE is a sandbox error result.
Handles both string errors (\"Error: ...\") and plist errors
like (:error \"...\") or (:violated t :reason \"...\")."
  (cond
   ((stringp value) (string-prefix-p "Error: " value))
   ((gptel-sandbox--error-plist-p value) t)
   (t nil)))

(defun gptel-sandbox--extract-error-message (value)
  "Extract error message from VALUE (string or plist)."
  (cond
   ((stringp value)
    (if (string-prefix-p "Error: " value)
        (substring value (length "Error: "))
      value))
   ((gptel-sandbox--error-plist-p value)
    (or (plist-get value :reason)
        (plist-get value :error)
        (format "Error: %S" value)))
   (t (format "%s" value))))

(defun gptel-sandbox--wrap-result (result)
  "Wrap RESULT for callback, converting error plists to error strings."
  (gptel-sandbox--format-result result))

(defun gptel-sandbox--format-result (result)
  "Convert RESULT to string, preferring gptel--to-string when available.
Error plists like (:error \"...\") or (:violated t :reason \"...\")
are converted to error strings."
  (condition-case err
      (if (gptel-sandbox--error-result-p result)
          (gptel-sandbox--format-error (gptel-sandbox--extract-error-message result))
        (let ((str (if (fboundp 'gptel--to-string)
                       (gptel--to-string result)
                     nil)))
          (if (stringp str) str (format "%s" result))))
    (error
     (format "Error: %s" (error-message-string err)))))

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
  (when (null callback)
    (error "Programmatic sandbox execute-tool requires a non-nil callback"))
  (unless (functionp callback)
    (error "Programmatic sandbox execute-tool requires a function callback, got: %S" callback))
  (unless (proper-list-p state)
    (error "Programmatic sandbox execute-tool requires a proper plist state, got: %S" state))
  (unless (hash-table-p env)
    (error "Programmatic sandbox execute-tool requires a hash table env, got: %S" env))
  (unless (or (symbolp tool-name) (stringp tool-name))
    (error "Programmatic tool name must be a symbol or string, got: %S" tool-name))
  (let* ((tool-spec (if (fboundp 'gptel-get-tool)
                        (gptel-get-tool tool-name)
                      nil)))
    (unless tool-spec
      (error "Unknown tool %s requested by Programmatic" tool-name))
    (unless (proper-list-p tool-spec)
      (error "Programmatic tool spec must be a proper list, got: %S" tool-spec))
    (let ((arg-values (gptel-sandbox--resolve-tool-args tool-spec arg-forms env)))
      (gptel-sandbox--check-tool tool-name tool-spec arg-values)
      (setf (plist-get state :tool-count) (1+ (or (plist-get state :tool-count) 0)))
      (when (> (plist-get state :tool-count) my/gptel-programmatic-max-tool-calls)
        (error "Programmatic exceeded max nested tool calls (%d)"
               my/gptel-programmatic-max-tool-calls))
      (condition-case err
          (let* ((tool-fn (gptel-tool-function tool-spec))
                 (_ (unless (functionp tool-fn)
                      (error "Tool %s has invalid :function property (got: %S)"
                             tool-name tool-fn)))
                 (invoke-tool
                  (lambda ()
                    (if (gptel-tool-async tool-spec)
                        (condition-case async-err
                            (apply tool-fn
                                   (lambda (result)
                                     (condition-case cb-err
                                         (funcall callback (gptel-sandbox--format-result result))
                                       (error (funcall callback
                                                       (gptel-sandbox--format-result
                                                        (gptel-sandbox--format-error
                                                         (error-message-string cb-err)))))))
                                   arg-values)
                          (error (funcall callback
                                          (gptel-sandbox--format-result
                                           (gptel-sandbox--format-error
                                            (error-message-string async-err))))))
                      (let ((result (condition-case inner-err
                                        (apply tool-fn arg-values)
                                      (error (gptel-sandbox--format-error (error-message-string inner-err))))))
                        (funcall callback (gptel-sandbox--format-result result)))))))
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
         (funcall callback (gptel-sandbox--format-error (error-message-string err))))))))

(defun gptel-sandbox--eval-statement (statement env state callback)
  "Evaluate sandbox STATEMENT with ENV and STATE, then CALLBACK.
CALLBACK receives a plist with one of the keys `:continue' or `:result'."
  (unless (hash-table-p env)
    (error "Programmatic eval-statement requires a hash table environment, got: %S" env))
  (unless (proper-list-p state)
    (error "Programmatic eval-statement requires a proper plist state, got: %S" state))
  (when (null statement)
    (error "Programmatic eval-statement requires a non-nil statement, got: nil"))
  (unless (consp statement)
    (error "Programmatic eval-statement requires a proper list statement, got: %S" statement))
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
                           (if (gptel-sandbox--error-result-p value)
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
     (unless (proper-list-p arg-forms)
       (error "Programmatic tool-call requires a proper list of arguments, got: %S" arg-forms))
     (gptel-sandbox--execute-tool
      (lambda (value)
        (if (gptel-sandbox--error-result-p value)
            (funcall callback (list :done t :result value))
          (gptel-sandbox--bind-last-value value env)
          (funcall callback (list :continue t :done nil))))
      tool-name arg-forms env state))
    (`(result ,expr)
     (funcall callback (list :done t :result (gptel-sandbox--format-result (gptel-sandbox--eval-expr expr env)))))
    (_
     (error "Unsupported statement in Programmatic sandbox: %S"
            (if (consp statement) (car statement) statement)))))

(defun gptel-sandbox--eval-progn (body env state callback)
  "Evaluate BODY forms sequentially, handling async tool-calls.
CALLBACK receives final outcome plist."
  (unless (hash-table-p env)
    (error "Programmatic eval-progn requires a hash table environment, got: %S" env))
  (unless (proper-list-p state)
    (error "Programmatic eval-progn requires a proper plist state, got: %S" state))
  (unless (proper-list-p body)
    (error "Programmatic eval-progn requires a proper list of forms, got: %S" body))
  (if (null body)
      (funcall callback (list :done t :result nil))
    (gptel-sandbox--eval-statement
     (car body) env state
     (lambda (outcome)
       (unless (proper-list-p outcome)
         (error "Programmatic eval-progn callback received invalid outcome, got: %S" outcome))
       (if (plist-get outcome :done)
           (funcall callback outcome)
         (gptel-sandbox--eval-progn (cdr body) env state callback))))))

(defun gptel-sandbox--run-forms (forms env state callback)
  "Run sandbox FORMS with ENV and STATE, then CALLBACK final result."
  (unless (proper-list-p forms)
    (error "Programmatic run-forms requires a proper list, got: %S" forms))
  (unless (hash-table-p env)
    (error "Programmatic run-forms requires a hash table env, got: %S" env))
  (unless (proper-list-p state)
    (error "Programmatic run-forms requires a proper plist state, got: %S" state))
  (unless (functionp callback)
    (error "Programmatic run-forms requires a function callback, got: %S" callback))
  (if (null forms)
      (funcall callback (gptel-sandbox--truncate-result
                         (format "Error: Programmatic execution finished without calling result (used %d tools)"
                                 (plist-get state :tool-count))))
    (gptel-sandbox--eval-statement
     (car forms) env state
     (lambda (outcome)
       (unless (proper-list-p outcome)
         (error "Programmatic run-forms callback received invalid outcome, got: %S" outcome))
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
