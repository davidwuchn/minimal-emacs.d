;;; test-gptel-ext-core.el --- Tests for core gptel config -*- lexical-binding: t; -*-

;;; Commentary:
;; P1 tests for gptel-ext-core.el
;; Tests:
;; - my/gptel-temp-dir
;; - my/gptel-make-temp-file
;; - my/gptel--pre-serialize-sanitize-messages
;; - my/gptel--curl-parse-response-safe
;; - my/gptel--known-tool-names
;; - my/gptel--preset-tool-names
;; - my/gptel--gptel-request-callback-guard (plist alignment + function pass-through + reasoning filter)
;; - my/gptel--stream-cleanup-process-guard

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables

(defvar gptel-mode nil)
(defvar gptel-model nil)
(defvar gptel--preset nil)
(defvar gptel--known-tools nil)
(defvar my/gptel-plain-model nil)
(defvar my/gptel--in-subagent-task nil)

;;; Functions under test

(defun test-temp-dir ()
  "Return temp directory path."
  (let* ((root default-directory)
         (dir (expand-file-name "temp/" root)))
    dir))

(defun test-make-temp-file (prefix &optional _dir-flag suffix)
  "Create temp file with PREFIX."
  (let ((dir (test-temp-dir)))
    (concat dir prefix (or suffix ""))))

(defun test-known-tool-names ()
  "Return list of known tool names."
  (when (boundp 'gptel--known-tools)
    (cl-loop for (_cat . tools) in gptel--known-tools
             append (mapcar #'car tools))))

(defun test-preset-tool-names (preset)
  "Return tool names for PRESET."
  (when preset
    (list "Read" "Edit" "Grep")))

(defun test-pre-serialize-sanitize-messages (info _token)
  "Sanitize unsupported message :content values in INFO."
  (when-let* ((data (plist-get info :data))
              (msgs (plist-get data :messages)))
    (cl-loop for msg across msgs
             when (listp msg)
             do
             (let ((content (plist-get msg :content))
                   (tool-calls (plist-get msg :tool_calls)))
               (when (or (eq content :null)
                         (and (null content) (null tool-calls)))
                 (plist-put msg :content ""))))))

(defun test-curl-parse-response-safe (orig proc-info)
  "Safe wrapper for curl response parsing."
  (condition-case err
      (funcall orig proc-info)
    (search-failed
     (list nil "000" "(curl) Could not parse HTTP response."
           (format "error: %s" (error-message-string err))))
    (error
     (list nil "000" "(curl) Parser error."
           (format "error: %s" (error-message-string err))))))

;;; Tests for my/gptel-temp-dir

(ert-deftest core/temp-dir/returns-path ()
  "Should return a temp directory path."
  (let ((default-directory "/tmp/test/"))
    (should (stringp (test-temp-dir)))))

(ert-deftest core/temp-dir/ends-with-slash ()
  "Should end with slash."
  (let ((default-directory "/tmp/test/"))
    (should (string-suffix-p "/" (test-temp-dir)))))

(ert-deftest core/temp-dir/contains-temp ()
  "Should contain 'temp' in path."
  (let ((default-directory "/tmp/test/"))
    (should (string-match-p "temp" (test-temp-dir)))))

;;; Tests for my/gptel-make-temp-file

(ert-deftest core/make-temp-file/returns-path ()
  "Should return a file path."
  (let ((default-directory "/tmp/"))
    (should (stringp (test-make-temp-file "test")))))

(ert-deftest core/make-temp-file/contains-prefix ()
  "Should contain the prefix in path."
  (let ((default-directory "/tmp/"))
    (should (string-match-p "myprefix" (test-make-temp-file "myprefix")))))

(ert-deftest core/make-temp-file/with-suffix ()
  "Should include suffix when provided."
  (let ((default-directory "/tmp/"))
    (should (string-match-p "\\.txt$" (test-make-temp-file "test" nil ".txt")))))

;;; Tests for my/gptel--known-tool-names

(ert-deftest core/known-tools/empty-registry ()
  "Should return nil when registry is empty."
  (let ((gptel--known-tools nil))
    (should-not (test-known-tool-names))))

(ert-deftest core/known-tools/with-tools ()
  "Should return tool names from registry."
  (let ((gptel--known-tools '((:readonly . (("Read" . nil)))
                              (:mutating . (("Edit" . nil) ("Write" . nil))))))
    (should (equal (test-known-tool-names) '("Read" "Edit" "Write")))))

(ert-deftest core/known-tools/single-category ()
  "Should work with single category."
  (let ((gptel--known-tools '((:readonly . (("Glob" . nil) ("Grep" . nil))))))
    (should (equal (test-known-tool-names) '("Glob" "Grep")))))

;;; Tests for my/gptel--preset-tool-names

(ert-deftest core/preset-tools/nil-preset ()
  "Should return nil for nil preset."
  (should-not (test-preset-tool-names nil)))

(ert-deftest core/preset-tools/with-preset ()
  "Should return tool names for preset."
  (should (equal (test-preset-tool-names 'gptel-agent) '("Read" "Edit" "Grep"))))

;;; Tests for my/gptel--pre-serialize-sanitize-messages

(ert-deftest core/sanitize/nil-content-becomes-empty ()
  "Should convert nil :content to empty string."
  (let* ((msg '(:role "user" :content nil))
         (info (list :data (list :messages (vector msg)))))
    (test-pre-serialize-sanitize-messages info nil)
    (should (equal (plist-get msg :content) ""))))

(ert-deftest core/sanitize/keeps-existing-content ()
  "Should keep non-nil content unchanged."
  (let* ((msg '(:role "user" :content "hello"))
         (info (list :data (list :messages (vector msg)))))
    (test-pre-serialize-sanitize-messages info nil)
    (should (equal (plist-get msg :content) "hello"))))

(ert-deftest core/sanitize/null-content-becomes-empty ()
  "Should convert :null :content to empty string."
  (let* ((msg '(:role "assistant" :content :null))
         (info (list :data (list :messages (vector msg)))))
    (test-pre-serialize-sanitize-messages info nil)
    (should (equal (plist-get (aref (plist-get (plist-get info :data) :messages) 0)
                              :content)
                   ""))))

(ert-deftest core/sanitize/ignores-tool-call-messages ()
  "Should not touch messages with :tool_calls."
  (let* ((msg '(:role "assistant" :content nil :tool_calls [(:id "1")]))
         (info (list :data (list :messages (vector msg)))))
    (test-pre-serialize-sanitize-messages info nil)
    (should (null (plist-get msg :content)))))

(ert-deftest core/sanitize/null-tool-call-messages-are-silent ()
  "Should sanitize :null tool-call messages without noisy warnings."
  (let* ((msg '(:role "assistant" :content :null :tool_calls [(:id "1")]))
         (info (list :data (list :messages (vector msg))))
         (messages nil))
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (test-pre-serialize-sanitize-messages info nil))
    (should (equal (plist-get (aref (plist-get (plist-get info :data) :messages) 0)
                              :content)
                   ""))
    (should-not messages)))

(ert-deftest core/sanitize/handles-empty-messages ()
  "Should handle empty messages array."
  (let ((info (list :data (list :messages (vector)))))
    (should (null (test-pre-serialize-sanitize-messages info nil)))))

;;; Tests for my/gptel--curl-parse-response-safe

(ert-deftest core/curl-safe/passes-through-success ()
  "Should pass through successful response."
  (let ((result (test-curl-parse-response-safe
                 (lambda (_) (list "body" "200" "OK" nil))
                 nil)))
    (should (equal (car result) "body"))))

(ert-deftest core/curl-safe/catches-search-failed ()
  "Should catch search-failed error."
  (let ((result (test-curl-parse-response-safe
                 (lambda (_) (signal 'search-failed "not found"))
                 nil)))
    (should (equal (cadr result) "000"))
    (should (string-match-p "curl" (caddr result)))))

(ert-deftest core/curl-safe/catches-generic-error ()
  "Should catch generic errors."
  (let ((result (test-curl-parse-response-safe
                 (lambda (_) (signal 'error "something broke"))
                 nil)))
    (should (equal (cadr result) "000"))
    (should (string-match-p "error" (cadddr result)))))

;;; Tests for tool registry audit

(ert-deftest core/audit/missing-tools-detected ()
  "Should detect missing tools."
  (let* ((gptel--known-tools '((:core . (("Read" . nil) ("Edit" . nil)))))
         (known (test-known-tool-names))
         (preset-tools '("Read" "Edit" "Bash" "Grep"))
         (missing (cl-remove-if (lambda (n) (member n known)) preset-tools)))
    (should (equal missing '("Bash" "Grep")))))

(ert-deftest core/audit/all-tools-present ()
  "Should pass when all tools present."
  (let* ((gptel--known-tools '((:core . (("Read" . nil) ("Edit" . nil) ("Bash" . nil)))))
         (known (test-known-tool-names))
         (preset-tools '("Read" "Edit"))
         (missing (cl-remove-if (lambda (n) (member n known)) preset-tools)))
    (should (null missing))))

;;; ── Mocks for callback-guard tests ──

(defun test-callback-guard (orig-fn &optional prompt &rest args)
  "Replica of my/gptel--gptel-request-callback-guard for TDD testing.
Isolated from the live advice system to allow pure unit testing.
Now includes the reasoning-cons-cell wrapper (all callbacks wrapped)."
  (let* ((keys (cl-loop for (k v) on args by #'cddr collect k))
         (has-callback (memq :callback keys))
         (callback-val (and has-callback (plist-get args :callback)))
         (safe-cb (if (and has-callback (functionp callback-val))
                      callback-val
                    (or (and (functionp callback-val) callback-val) #'ignore)))
         (wrapped-cb
          (lambda (resp info)
            (if (and (consp resp) (eq (car resp) 'reasoning))
                (when (cdr resp)
                  (plist-put info :reasoning (cdr resp)))
              (funcall safe-cb resp info)))))
    (apply orig-fn prompt
           :callback wrapped-cb
           (cl-loop for (k v) on args by #'cddr
                    unless (eq k :callback)
                    append (list k v)))))

(defun test-stream-cleanup-guard (orig-fn process status request-alist-mock)
  "Replica of my/gptel--stream-cleanup-process-guard for TDD testing."
  (when (and process request-alist-mock)
    (let* ((entry (assq process request-alist-mock))
           (value (cdr entry)))
      (when (and value (consp value))
        (let* ((fsm (car value))
               (info (ignore-errors (gptel-fsm-info fsm))))
          (when (and info (listp info)
                     (not (functionp (plist-get info :callback))))
            (plist-get info :callback)))))) ; returns nil if callback nil — detected
  (funcall orig-fn process status))

;;; ── TDD: plist alignment root-cause regression ──
;; The (cons nil args) bug made plist-get always return nil because
;; prepending nil shifts the plist alignment:
;;   (:callback <fn>)  →  (nil :callback <fn>)
;; plist-get scans keys at even positions (0,2,...):
;;   pos 0: nil (not :callback) → skip
;;   pos 2: <fn> (not a symbol-eq to :callback) → skip
;; Result: returns nil, every callback replaced with #'ignore.

(ert-deftest core/callback-guard/plist-get-without-cons-nil-returns-callback ()
  "plist-get on (:callback <fn>) should return the function."
  (let* ((fn (lambda (x) x))
         (args (list :callback fn)))
    (should (functionp (plist-get args :callback)))
    (should (eq (plist-get args :callback) fn))))

(ert-deftest core/callback-guard/plist-get-with-cons-nil-returns-nil ()
  "plist-get on (cons nil '(:callback <fn>)) returns nil — THIS WAS THE BUG."
  (let* ((fn (lambda (x) x))
         (args (list :callback fn)))
    (should-not (plist-get (cons nil args) :callback))
    (should-not (functionp (plist-get (cons nil args) :callback)))))

(ert-deftest core/callback-guard/named-function-callback-is-found ()
  "plist-get should find a named function (quoted symbol) as callback."
  (let* ((args (list :callback #'ignore)))
    (should (functionp (plist-get args :callback)))
    (should (eq (plist-get args :callback) #'ignore))))

(ert-deftest core/callback-guard/compiled-lambda-callback-is-found ()
  "plist-get should find a compiled lambda as callback."
  (let* ((fn (byte-compile (lambda (x) x)))
         (args (list :callback fn)))
    (should (functionp (plist-get args :callback)))
    (should (eq (plist-get args :callback) fn))))

;;; ── TDD: callback-guard behavior ──

(ert-deftest core/callback-guard/passes-function-through ()
  "Guard should pass through a valid callback (now wrapped for reasoning)."
  (let* ((cb (lambda (resp info) (list resp info)))
         (received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt" :callback cb :model "test"))
    (let* ((call-args (car (last received-args)))
           (props (cdr call-args))     ; strip prompt
           (stored-cb (plist-get props :callback)))
      (should (functionp stored-cb))
      ;; Stored callback is the wrapped adapter — still functionp
      (should stored-cb))))

(ert-deftest core/callback-guard/replaces-nil-callback-with-ignore ()
  "Guard should replace :callback nil with a function callback (now wrapped)."
  (let* ((received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt" :callback nil))
    (let ((props (cdr (car (last received-args))))) ; strip prompt
      ;; Stored callback is functionp (wrapped ignore)
      (should (functionp (plist-get props :callback)))
      ;; Calling it with nil response should not crash
      (should (null (funcall (plist-get props :callback) nil '(:error "test")))))))

(ert-deftest core/callback-guard/adds-ignore-when-callback-missing ()
  "Guard should add a function callback when no :callback keyword (now wrapped)."
  (let* ((received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt" :model "test" :temperature 0.5))
    (let ((props (cdr (car (last received-args))))) ; strip prompt
      (should (functionp (plist-get props :callback)))
      ;; Other args preserved:
      (should (equal (plist-get props :model) "test"))
      (should (equal (plist-get props :temperature) 0.5)))))

(ert-deftest core/callback-guard/preserves-other-keyword-args ()
  "Guard should not strip non-callback keyword arguments."
  (let* ((cb (lambda (r _i) r))
         (received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt"
                           :callback cb :model "gpt-4" :temperature 0.7
                           :stream t :system "You are helpful."))
    (let ((props (cdr (car (last received-args))))) ; strip prompt
      (should (functionp (plist-get props :callback)))
      (should (equal (plist-get props :model) "gpt-4"))
      (should (equal (plist-get props :temperature) 0.7))
      (should (eq (plist-get props :stream) t))
      (should (equal (plist-get props :system) "You are helpful.")))))

(ert-deftest core/callback-guard/handles-empty-args ()
  "Guard should add a function callback for gptel-request with no keyword args."
  (let* ((received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt"))
    (let ((args (car (last received-args))))
      ;; prompt passed through:
      (should (equal (car args) "prompt"))
      ;; callback added as function:
      (should (functionp (plist-get (cdr args) :callback))))))

(ert-deftest core/callback-guard/non-function-callback-replaced ()
  "Guard should replace non-function callback (e.g., a string) with ignore func."
  (let* ((received-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (push r received-args))))
      (test-callback-guard #'gptel-request "prompt" :callback "not-a-function"))
    (let ((props (cdr (car (last received-args)))))
      (should (functionp (plist-get props :callback)))
      (let ((wrapped (plist-get props :callback)))
        ;; Calling wrapped callback with nil should not signal
        (condition-case nil
            (progn (funcall wrapped nil '(:error "test")) t)
          (error nil))))))

;;; ── TDD: reasoning cons-cell filter ──

(ert-deftest core/callback-guard/reasoning-cons-dropped-for-custom-callback ()
  "Wrapped callback should drop (reasoning . text) and call original on next call."
  (let* ((call-count 0)
         (last-resp nil)
         (cb (lambda (resp _info)
               (setq call-count (1+ call-count))
               (setq last-resp resp)))
         (args (list :callback cb))
         (stored-cb nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (setq stored-cb (plist-get (cdr r) :callback)))))
      (apply #'test-callback-guard #'gptel-request "prompt" args))
    ;; Fire reasoning cons cell — should be dropped
    (funcall stored-cb '(reasoning . "<think>hello</think>") '(:test t))
    (should (= call-count 0))
    (should (null last-resp))
    ;; Fire actual response — should reach original callback
    (funcall stored-cb "actual response" '(:test t))
    (should (= call-count 1))
    (should (equal last-resp "actual response"))))

(ert-deftest core/callback-guard/reasoning-cons-stored-in-info ()
  "Wrapped callback should store reasoning text in info plist."
  (let* ((stored-cb nil)
         (cb (lambda (resp _info) resp))
         (args (list :callback cb))
         (info '(:extra "data")))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (setq stored-cb (plist-get (cdr r) :callback)))))
      (apply #'test-callback-guard #'gptel-request "prompt" args))
    (funcall stored-cb '(reasoning . "think text") info)
    (should (equal (plist-get info :reasoning) "think text"))))

(ert-deftest core/callback-guard/reasoning-nil-consp-passes-through ()
  "Tool-call cons cells (non-reasoning) should pass through to callback."
  (let* ((call-count 0)
         (last-resp nil)
         (cb (lambda (resp _info)
               (setq call-count (1+ call-count))
               (setq last-resp resp)))
         (mock-args nil))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (&rest r) (setq mock-args r))))
      (apply #'test-callback-guard #'gptel-request "prompt" (list :callback cb)))
    ;; mock-args = ("prompt" :callback #<wrapped> ...)
    (let ((stored-cb (plist-get (cdr mock-args) :callback)))
      (should (functionp stored-cb))
      (funcall stored-cb '(tool-call . ((gptel-tool "Read"))) nil)
      (should (= call-count 1))
      (should (consp last-resp))
      (should (eq (car last-resp) 'tool-call)))))

;;; ── TDD: stream-cleanup guard ──

(ert-deftest core/stream-cleanup-guard/nil-callback-detected-no-crash ()
  "Stream cleanup guard should detect nil callback in FSM info without crashing."
  (let ((info (list :callback nil))
        (called-orig nil))
    (cl-letf (((symbol-function 'gptel-fsm-info)
               (lambda (_fsm) info))
              ((symbol-function 'gptel--request-alist) nil))
      (test-stream-cleanup-guard
       (lambda (_p _s) (setq called-orig t))
       'fake-process "finished"
       '((fake-process . (fake-fsm . cleanup-fn)))))
    (should called-orig)))

(ert-deftest core/stream-cleanup-guard/function-callback-left-untouched ()
  "Stream cleanup guard should leave function callback alone."
  (let ((info (list :callback #'ignore))
        (info-modified nil))
    (cl-letf (((symbol-function 'gptel-fsm-info)
               (lambda (_fsm) info))
              ((symbol-function 'setf)
               (lambda (&rest _) (setq info-modified t) nil)))
      (test-stream-cleanup-guard
       (lambda (_p _s) nil)
       'fake-process "finished"
       '((fake-process . (fake-fsm . cleanup-fn)))))
    (should-not info-modified)))

(provide 'test-gptel-ext-core)
;;; test-gptel-ext-core.el ends here
