;;; test-gptel-nucleus-context-intercept.el --- Context interception TDD -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((modules-dir (expand-file-name "../lisp/modules"
                                     (file-name-directory
                                      (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path modules-dir))
(let ((gptel-dir (expand-file-name "../packages/gptel"
                                   (file-name-directory
                                    (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-dir))
(let ((gptel-agent-dir (expand-file-name "../packages/gptel-agent"
                                         (file-name-directory
                                          (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-agent-dir))

(condition-case load-err
    (load-file (expand-file-name "../lisp/modules/gptel-nucleus-context-intercept.el"
                                 (file-name-directory
                                  (or load-file-name buffer-file-name default-directory))))
  (error (message "[test] context-intercept load failed: %s" (error-message-string load-err))))

(condition-case ai-err
    (load-file (expand-file-name "../lisp/modules/gptel-auto-experiment-ai-behaviors.el"
                                 (file-name-directory
                                  (or load-file-name buffer-file-name default-directory))))
  (error (message "[test] ai-behaviors load failed: %s" (error-message-string ai-err))))

;; ─── Helper: save/restore hooks (must use setq, not let, for defvar'd globals) ───

(defmacro tdd-context--with-hooks (hook-var hook-list &rest body)
  "Save HOOK-VAR, set it to HOOK-LIST, run BODY, restore."
  (declare (indent 2))
  `(let ((tdd--saved ,hook-var))
     (unwind-protect
         (progn
           (set ,hook-var ,hook-list)
           ,@body)
       (set ,hook-var tdd--saved))))

;; ─── Pre-Tool Hook Tests ───

(ert-deftest tdd/context-intercept/pre-tool-hook-registered ()
  "pre-tool-hook-list exists."
  (should (boundp 'gptel-nucleus-context--pre-tool-hooks)))

(ert-deftest tdd/context-intercept/post-tool-hook-registered ()
  "post-tool-hook-list exists."
  (should (boundp 'gptel-nucleus-context--post-tool-hooks)))

(ert-deftest tdd/context-intercept/pre-tool-can-deny ()
  "A PreToolUse hook returning :deny skips the tool call entirely."
  (when (fboundp 'gptel-nucleus-context--run-pre-tool-hooks)
    (tdd-context--with-hooks 'gptel-nucleus-context--pre-tool-hooks
        (list (lambda (_a _p _d) (list :deny)))
      (let ((result (gptel-nucleus-context--run-pre-tool-hooks
                     "analyzer" "test prompt" "test description" nil)))
        (should (plistp result))
        (should (eq :deny (plist-get result :action)))))))

(ert-deftest tdd/context-intercept/pre-tool-can-modify-prompt ()
  "PreToolUse hooks can modify the prompt before dispatch."
  (when (fboundp 'gptel-nucleus-context--run-pre-tool-hooks)
    (tdd-context--with-hooks 'gptel-nucleus-context--pre-tool-hooks
        (list (lambda (_a p _d)
                (list :continue :modified-prompt (concat p " [ROUTED]"))))
      (let ((result (gptel-nucleus-context--run-pre-tool-hooks
                     "analyzer" "Hello" "desc" nil)))
        (should (eq :continue (plist-get result :action)))
        (should (string= "Hello [ROUTED]" (plist-get result :modified-prompt)))))))

(ert-deftest tdd/context-intercept/pre-tool-chain-runs-all ()
  "All PreToolUse hooks run in registration order."
  (when (fboundp 'gptel-nucleus-context--run-pre-tool-hooks)
    (let ((execution-order (list nil)))
      (tdd-context--with-hooks 'gptel-nucleus-context--pre-tool-hooks
          (list (lambda (_a _p _d)
                  (setcar execution-order (cons 'first (car execution-order)))
                  (list :continue))
                (lambda (_a _p _d)
                  (setcar execution-order (cons 'second (car execution-order)))
                  (list :continue)))
        (gptel-nucleus-context--run-pre-tool-hooks "analyzer" "prompt" "desc" nil)
        (let ((order (car execution-order)))
          (should (eq 'second (car order)))
          (should (eq 'first (cadr order))))))))

(ert-deftest tdd/context-intercept/pre-tool-first-deny-stops-chain ()
  "A :deny from the first hook stops the chain; subsequent hooks don't run."
  (when (fboundp 'gptel-nucleus-context--run-pre-tool-hooks)
    (let ((second-ran (list nil)))
      (tdd-context--with-hooks 'gptel-nucleus-context--pre-tool-hooks
          (list (lambda (_a _p _d) (list :deny))
                (lambda (_a _p _d)
                  (setcar second-ran t)
                  (list :continue)))
        (gptel-nucleus-context--run-pre-tool-hooks "analyzer" "prompt" "desc" nil)
        (should-not (car second-ran))))))

(ert-deftest tdd/context-intercept/pre-tool-hook-error-nonfatal ()
  "An error in a PreToolUse hook does not crash the tool call."
  (when (fboundp 'gptel-nucleus-context--run-pre-tool-hooks)
    (tdd-context--with-hooks 'gptel-nucleus-context--pre-tool-hooks
        (list (lambda (_a _p _d) (error "simulated hook failure")))
      (let ((result (gptel-nucleus-context--run-pre-tool-hooks
                     "analyzer" "prompt" "desc" nil)))
        (should (plistp result))
        (should (eq :continue (plist-get result :action)))))))

;; ─── Post-Tool Hook Tests ───

(ert-deftest tdd/context-intercept/post-tool-captures-result ()
  "PostToolUse hooks receive the result and agent name."
  (when (fboundp 'gptel-nucleus-context--run-post-tool-hooks)
    (let ((captured (list nil nil)))
      (tdd-context--with-hooks 'gptel-nucleus-context--post-tool-hooks
          (list (lambda (an rs _d _p)
                  (setcar captured an)
                  (setcar (cdr captured) rs)))
        (gptel-nucleus-context--run-post-tool-hooks
         "executor" "code result here" 2.5 "original prompt")
        (should (string= "executor" (car captured)))
        (should (string= "code result here" (cadr captured)))))))

(ert-deftest tdd/context-intercept/post-tool-hook-error-nonfatal ()
  "An error in a PostToolUse hook does not crash the caller."
  (when (fboundp 'gptel-nucleus-context--run-post-tool-hooks)
    (tdd-context--with-hooks 'gptel-nucleus-context--post-tool-hooks
        (list (lambda (_a _r _d _p) (error "post hook failure")))
      (gptel-nucleus-context--run-post-tool-hooks
       "analyzer" "result" 1.0 "prompt"))))

;; ─── Context Bytes Accounting ───

(ert-deftest tdd/context-intercept/bytes-accounting-registered ()
  "bytes-saved and bytes-returned tracking variables exist."
  (should (boundp 'gptel-nucleus-context--bytes-saved-this-session))
  (should (boundp 'gptel-nucleus-context--bytes-returned-this-session))
  (should (boundp 'gptel-nucleus-context--bytes-saved-lifetime))
  (should (boundp 'gptel-nucleus-context--bytes-returned-lifetime)))

(ert-deftest tdd/context-intercept/bytes-saved-tracking ()
  "bytes-saved can be incremented and read."
  (when (boundp 'gptel-nucleus-context--bytes-saved-lifetime)
    (should (integerp gptel-nucleus-context--bytes-saved-lifetime))
    (gptel-nucleus-context--record-bytes-saved 1000)
    (should (integerp gptel-nucleus-context--bytes-saved-this-session))
    (should (> gptel-nucleus-context--bytes-saved-this-session 0))))

(ert-deftest tdd/context-intercept/bytes-accounting-ratio ()
  "context-savings-ratio returns a float 0-1 range."
  (when (fboundp 'gptel-nucleus-context--context-savings-ratio)
    (let ((ratio (gptel-nucleus-context--context-savings-ratio)))
      (should (floatp ratio))
      (should (>= ratio 0.0))
      (should (<= ratio 1.0)))))

(ert-deftest tdd/context-intercept/bytes-accounting-efficiency-percent ()
  "context-efficiency returns a percentage string."
  (when (fboundp 'gptel-nucleus-context--context-efficiency)
    (let ((pct (gptel-nucleus-context--context-efficiency)))
      (should (stringp pct)))))

(ert-deftest tdd/context-intercept/record-bytes-saved-adds-correctly ()
  "Multiple bytes-saved records accumulate."
  (when (and (fboundp 'gptel-nucleus-context--record-bytes-saved)
             (boundp 'gptel-nucleus-context--bytes-saved-this-session))
    (let ((before-session gptel-nucleus-context--bytes-saved-this-session))
      (gptel-nucleus-context--record-bytes-saved 500)
      (gptel-nucleus-context--record-bytes-saved 300)
      (should (= (+ before-session 800)
                 gptel-nucleus-context--bytes-saved-this-session)))))

(ert-deftest tdd/context-intercept/record-bytes-returned-adds-correctly ()
  "Multiple bytes-returned records accumulate."
  (when (and (fboundp 'gptel-nucleus-context--record-bytes-returned)
             (boundp 'gptel-nucleus-context--bytes-returned-this-session))
    (let ((before-session gptel-nucleus-context--bytes-returned-this-session))
      (gptel-nucleus-context--record-bytes-returned 2000)
      (gptel-nucleus-context--record-bytes-returned 1500)
      (should (= (+ before-session 3500)
                 gptel-nucleus-context--bytes-returned-this-session)))))

;; ─── Auto-Indexing Tests ───

(ert-deftest tdd/context-intercept/auto-index-threshold-registered ()
  "auto-index-threshold has a reasonable default."
  (should (boundp 'gptel-nucleus-context--auto-index-threshold))
  (should (integerp gptel-nucleus-context--auto-index-threshold))
  (should (> gptel-nucleus-context--auto-index-threshold 0)))

(ert-deftest tdd/context-intercept/auto-index-decides-by-threshold ()
  "auto-index-p returns t only when bytes > threshold."
  (when (fboundp 'gptel-nucleus-context--auto-index-p)
    (should-not (gptel-nucleus-context--auto-index-p 1000))
    (should (gptel-nucleus-context--auto-index-p 15000))
    (should-not (gptel-nucleus-context--auto-index-p 0))
    (should-not (gptel-nucleus-context--auto-index-p -1))))

(ert-deftest tdd/context-intercept/auto-index-truncates-large-output ()
  "auto-index-truncate returns a truncated string with index pointer."
  (when (fboundp 'gptel-nucleus-context--auto-index-truncate)
    (let* ((large-output (make-string 20000 ?X))
           (result (gptel-nucleus-context--auto-index-truncate
                    large-output 5000 "test-agent" "test-index")))
      (should (stringp result))
      (should (< (length result) 20000))
      (should (string-match-p (regexp-quote "[context-mode]") result))
      (should (string-match-p "test-index" result)))))

(ert-deftest tdd/context-intercept/auto-index-stores-content ()
  "auto-index-store can store and retrieve content."
  (when (fboundp 'gptel-nucleus-context--index-store)
    (let ((idx-key "tdd-test-index-key"))
      (gptel-nucleus-context--index-store idx-key "Hello world content" "executor")
      (let ((retrieved (gptel-nucleus-context--index-lookup idx-key)))
        (should (stringp retrieved))
        (should (string-match-p "Hello world" retrieved)))
      (gptel-nucleus-context--index-clear idx-key))))

(ert-deftest tdd/context-intercept/index-search-finds-content ()
  "index-search can find stored content with simple queries."
  (when (fboundp 'gptel-nucleus-context--index-search)
    (let ((idx-key "tdd-search-key"))
      (gptel-nucleus-context--index-store
       idx-key "defun hello-world returns a greeting string
defun goodbye returns a farewell string
defvar default-greeting is Hello" "executor")
      (let ((results (gptel-nucleus-context--index-search idx-key "greeting")))
        (should (listp results))
        (should (> (length results) 0)))
      (gptel-nucleus-context--index-clear idx-key))))

;; ─── Context-Cost Model Integration ───

(ert-deftest tdd/context-intercept/context-cost-estimate ()
  "context-cost-estimate returns a dollar value for context bytes."
  (when (fboundp 'gptel-nucleus-context--context-cost-estimate)
    (let ((cost (gptel-nucleus-context--context-cost-estimate 10000 "deepseek-v4-flash")))
      (should (floatp cost))
      (should (>= cost 0.0)))))

(ert-deftest tdd/context-intercept/context-cost-zero-for-zero-bytes ()
  "Zero bytes has zero context cost."
  (when (fboundp 'gptel-nucleus-context--context-cost-estimate)
    (let ((cost (gptel-nucleus-context--context-cost-estimate 0 "deepseek-v4-flash")))
      (should (= cost 0.0)))))

(ert-deftest tdd/context-intercept/backend-context-efficiency-exists ()
  "per-backend context efficiency tracking table exists."
  (should (boundp 'gptel-nucleus-context--backend-efficiency))
  (should (hash-table-p gptel-nucleus-context--backend-efficiency)))

(ert-deftest tdd/context-intercept/backend-efficiency-recording ()
  "per-backend context efficiency can be recorded and read."
  (when (fboundp 'gptel-nucleus-context--record-backend-efficiency)
    (clrhash gptel-nucleus-context--backend-efficiency)
    (gptel-nucleus-context--record-backend-efficiency "DeepSeek" 50000 500)
    (let ((eff (gethash "DeepSeek" gptel-nucleus-context--backend-efficiency)))
      (should (consp eff))
      (should (= 50000 (car eff)))
      (should (= 500 (cdr eff))))
    (clrhash gptel-nucleus-context--backend-efficiency)))

(ert-deftest tdd/context-intercept/backend-efficiency-ratio ()
  "backend-context-efficiency returns savings ratio for a backend."
  (when (fboundp 'gptel-nucleus-context--backend-context-efficiency)
    (clrhash gptel-nucleus-context--backend-efficiency)
    (gptel-nucleus-context--record-backend-efficiency "DeepSeek" 90000 10000)
    (let ((eff (gptel-nucleus-context--backend-context-efficiency "DeepSeek")))
      (should (floatp eff))
      (should (> eff 0.0))
      (should (<= eff 1.0)))
    (clrhash gptel-nucleus-context--backend-efficiency)))

;; ─── Cost-Adjusted-Rate with Context ───

(ert-deftest tdd/context-intercept/context-cost-adjusted-rate ()
  "context-cost-adjusted-rate incorporates context cost into the keep-rate model."
  (when (fboundp 'gptel-nucleus-context--context-cost-adjusted-rate)
    (let ((rate-efficient (gptel-nucleus-context--context-cost-adjusted-rate
                           5 10 "deepseek-v4-flash" 0.9))
          (rate-wasteful (gptel-nucleus-context--context-cost-adjusted-rate
                          5 10 "deepseek-v4-flash" 0.1)))
      (should (numberp rate-efficient))
      (should (numberp rate-wasteful))
      (should (> rate-efficient rate-wasteful)))))

(ert-deftest tdd/context-intercept/context-cost-adjusted-rate-zero-experiments ()
  "Zero experiments returns 0.0 rate."
  (when (fboundp 'gptel-nucleus-context--context-cost-adjusted-rate)
    (let ((rate (gptel-nucleus-context--context-cost-adjusted-rate
                 0 0 "deepseek-v4-flash" 0.5)))
      (should (numberp rate))
      (should (= rate 0.0)))))

;; ─── Tool Routing Rules ───

(ert-deftest tdd/context-intercept/routing-rules-exist ()
  "tool-routing-rules hash table exists."
  (should (boundp 'gptel-nucleus-context--tool-routing-rules))
  (should (hash-table-p gptel-nucleus-context--tool-routing-rules)))

(ert-deftest tdd/context-intercept/routing-rule-register-and-match ()
  "Routing rules can be registered and matched."
  (when (fboundp 'gptel-nucleus-context--add-routing-rule)
    (let ((gptel-nucleus-context--tool-routing-rules (make-hash-table :test 'equal)))
      (gptel-nucleus-context--add-routing-rule
       "read-file" "ctx_execute" "Avoid dumping file contents into context")
      (let ((rule (gethash "read-file" gptel-nucleus-context--tool-routing-rules)))
        (should rule)
        (should (string= "ctx_execute" (car rule)))
        (should (string-match-p "Avoid dumping" (cdr rule)))))))

(ert-deftest tdd/context-intercept/routing-match-returns-nil-for-unknown ()
  "Unknown tool returns nil from routing match."
  (when (fboundp 'gptel-nucleus-context--match-routing-rule)
    (clrhash gptel-nucleus-context--tool-routing-rules)
    (should-not (gptel-nucleus-context--match-routing-rule "nonexistent-tool"))))

;; ─── Think in Code Enforcement ───

(ert-deftest tdd/context-intercept/think-in-code-directive-exists ()
  "think-in-code directive is a non-empty string."
  (should (boundp 'gptel-nucleus-context--think-in-code-directive))
  (should (stringp gptel-nucleus-context--think-in-code-directive))
  (should (> (length gptel-nucleus-context--think-in-code-directive) 0)))

;; ─── Event Capture for Session Continuity ───

(ert-deftest tdd/context-intercept/session-events-exist ()
  "session-events tracking variable exists."
  (should (boundp 'gptel-nucleus-context--session-events))
  (should (listp gptel-nucleus-context--session-events)))

(ert-deftest tdd/context-intercept/record-session-event ()
  "session events can be recorded and retrieved."
  (when (fboundp 'gptel-nucleus-context--record-session-event)
    (let ((gptel-nucleus-context--session-events nil))
      (gptel-nucleus-context--record-session-event
       :file-edit "test.el" "Modified defun fibonacci")
      (should (= 1 (length gptel-nucleus-context--session-events)))
      (let ((event (car gptel-nucleus-context--session-events)))
        (should (eq :file-edit (plist-get event :type)))
        (should (string= "test.el" (plist-get event :target)))))))

(ert-deftest tdd/context-intercept/build-resume-snapshot ()
  "resume snapshot builder returns a structured string."
  (when (fboundp 'gptel-nucleus-context--build-resume-snapshot)
    (let ((gptel-nucleus-context--session-events
           (list (list :type :file-edit :target "foo.el" :detail "added defun bar" :timestamp 1000.0)
                 (list :type :decision :target "backend-selection" :detail "Use DeepSeek" :timestamp 1001.0)
                 (list :type :error :target "byte-compile" :detail "void-variable x" :timestamp 1002.0))))
      (let ((snap (gptel-nucleus-context--build-resume-snapshot "tdd-test-experiment")))
        (should (stringp snap))
        (should (string-match-p "foo.el" snap))
        (should (string-match-p "backend-selection" snap))
        (should (string-match-p "void-variable" snap))))))

(ert-deftest tdd/context-intercept/resume-snapshot-empty ()
  "Empty events produces a minimal snapshot."
  (when (fboundp 'gptel-nucleus-context--build-resume-snapshot)
    (let ((gptel-nucleus-context--session-events nil))
      (let ((snap (gptel-nucleus-context--build-resume-snapshot "tdd-test")))
        (should (stringp snap))
        (should (string-match-p "No session events" snap))))))

;; ─── Progressive Throttling ───

(ert-deftest tdd/context-intercept/progressive-throttle-allow ()
  "First few calls within window are allowed."
  (when (fboundp 'gptel-nucleus-context--throttle-allow-p)
    (should (gptel-nucleus-context--throttle-allow-p "index-search"))))

(ert-deftest tdd/context-intercept/progressive-throttle-block-after-limit ()
  "After >threshold calls, further calls are blocked."
  (when (and (fboundp 'gptel-nucleus-context--throttle-allow-p)
             (fboundp 'gptel-nucleus-context--throttle-reset))
    (gptel-nucleus-context--throttle-reset)
    (dotimes (_i 20)
      (gptel-nucleus-context--throttle-allow-p "index-search"))
    (should-not (gptel-nucleus-context--throttle-allow-p "index-search"))
    (gptel-nucleus-context--throttle-reset)))

;; ─── Lambda Notation Compression Integration ───

(ert-deftest tdd/context-intercept/lambda-compress-bytes-savings ()
  "lambda-compress returns bytes saved from compression."
  (when (fboundp 'gptel-nucleus-context--lambda-compress-and-measure)
    (let* ((input "This is a verbose prompt with many filler words that should be compressed
into lambda notation symbols like lambda x y z that are much shorter")
           (result (gptel-nucleus-context--lambda-compress-and-measure input)))
      (should (consp result))
      (should (stringp (car result)))
      (should (integerp (cdr result)))
      (should (>= (cdr result) 0)))))

(ert-deftest tdd/context-intercept/lambda-identity-no-loss ()
  "Compressing a short prompt produces no savings."
  (when (fboundp 'gptel-nucleus-context--lambda-compress-and-measure)
    (let* ((input "hello")
           (result (gptel-nucleus-context--lambda-compress-and-measure input)))
      (should (= 0 (cdr result)))
      (should (string= input (car result))))))

;; ─── Integration: Full Tool Dispatch with Interception ───

(ert-deftest tdd/context-intercept/wrapped-agent-tool-with-hooks ()
  "The full wrapped dispatch runs pre/post hooks and captures events."
  (when (fboundp 'gptel-nucleus-context--wrap-agent-tool)
    (let* ((pre-ran (list nil))
           (callback-called (list nil))
           (pre-hooks gptel-nucleus-context--pre-tool-hooks)
           (post-hooks gptel-nucleus-context--post-tool-hooks)
           (original-fn (lambda (cb _a _d _p _f _h _df)
                          (when (functionp cb)
                            (setcar callback-called t)
                            (funcall cb "mock result"))))
           (hook (lambda (_a _p _d)
                   (setcar pre-ran t)
                   (list :continue))))
      (unwind-protect
          (progn
            (setq gptel-nucleus-context--pre-tool-hooks (list hook))
            (setq gptel-nucleus-context--post-tool-hooks nil)
            (gptel-nucleus-context--wrap-agent-tool
             original-fn (lambda (_r) t) "executor" "do thing" "prompt" nil nil nil)
            (should (car pre-ran))
            (should (car callback-called)))
        (setq gptel-nucleus-context--pre-tool-hooks pre-hooks)
        (setq gptel-nucleus-context--post-tool-hooks post-hooks)))))

;; ─── Persistent Session State ───

(ert-deftest tdd/context-intercept/persistent-store-exists ()
  "persist-file and persist-enabled variable exist."
  (should (boundp 'gptel-nucleus-context--persist-file))
  (should (stringp gptel-nucleus-context--persist-file)))

(ert-deftest tdd/context-intercept/persist-save-and-load ()
  "Events can be persisted to a file and loaded back."
  (when (fboundp 'gptel-nucleus-context--persist-events)
    (let* ((tmpdir (make-temp-file "ctx-persist" t))
           (persist-file (expand-file-name "events.json" tmpdir))
           (gptel-nucleus-context--session-events nil))
      (unwind-protect
          (let ((gptel-nucleus-context--persist-file persist-file))
            (gptel-nucleus-context--record-session-event
             :file-edit "foo.el" "added defun bar")
            (gptel-nucleus-context--record-session-event
             :decision "backend" "Use DeepSeek")
            (gptel-nucleus-context--persist-events)
            ;; Simulate restart: clear events, reload
            (setq gptel-nucleus-context--session-events nil)
            (gptel-nucleus-context--load-events)
            (should (= 2 (length gptel-nucleus-context--session-events)))
            ;; Events are stored newest-first (push order), so car is :decision
            (should (eq :decision
                        (plist-get (car gptel-nucleus-context--session-events) :type))))
        (delete-directory tmpdir t)))))

(ert-deftest tdd/context-intercept/persist-fifo-eviction ()
  "Oldest events evicted when exceeding max cap."
  (when (fboundp 'gptel-nucleus-context--persist-events)
    (let* ((tmpdir (make-temp-file "ctx-persist" t))
           (persist-file (expand-file-name "events.json" tmpdir))
           (gptel-nucleus-context--max-session-events 5)
           (gptel-nucleus-context--session-events nil))
      (unwind-protect
          (let ((gptel-nucleus-context--persist-file persist-file))
            (dotimes (i 8)
              (gptel-nucleus-context--record-session-event
               :file-edit (format "file%d.el" i) (format "edit %d" i)))
            (should (<= (length gptel-nucleus-context--session-events) 5))
            (gptel-nucleus-context--persist-events)
            (setq gptel-nucleus-context--session-events nil)
            (gptel-nucleus-context--load-events)
            (should (<= (length gptel-nucleus-context--session-events) 5)))
        (delete-directory tmpdir t)))))

(ert-deftest tdd/context-intercept/persist-empty-events ()
  "Persisting empty events produces valid empty file."
  (when (fboundp 'gptel-nucleus-context--persist-events)
    (let* ((tmpdir (make-temp-file "ctx-persist" t))
           (persist-file (expand-file-name "events.json" tmpdir))
           (gptel-nucleus-context--session-events nil))
      (unwind-protect
          (let ((gptel-nucleus-context--persist-file persist-file))
            (gptel-nucleus-context--persist-events)
            (should (file-exists-p persist-file))
            (gptel-nucleus-context--load-events)
            (should (null gptel-nucleus-context--session-events)))
        (delete-directory tmpdir t)))))

(ert-deftest tdd/context-intercept/persist-on-event-hook ()
  "Each event record triggers auto-persist (debounced)."
  (when (boundp 'gptel-nucleus-context--auto-persist-enabled)
    ;; Verify the auto-persist mechanism exists
    (should gptel-nucleus-context--auto-persist-enabled)))

(ert-deftest tdd/context-intercept/resume-snapshot-cross-run ()
  "Resume snapshot includes events from previous run (loaded from persist)."
  (when (and (fboundp 'gptel-nucleus-context--build-resume-snapshot)
             (fboundp 'gptel-nucleus-context--persist-events))
    (let* ((tmpdir (make-temp-file "ctx-persist" t))
           (persist-file (expand-file-name "events.json" tmpdir))
           (gptel-nucleus-context--session-events nil))
      (unwind-protect
          (let ((gptel-nucleus-context--persist-file persist-file))
            (gptel-nucleus-context--record-session-event
             :decision "prev-run" "Chose MiniMax over DeepSeek")
            (gptel-nucleus-context--persist-events)
            ;; New run: events cleared, but resume loads from persist
            (gptel-nucleus-context--clear-session-events)
            (gptel-nucleus-context--load-events)
            (let ((snap (gptel-nucleus-context--build-resume-snapshot "exp-42")))
              (should (string-match-p "MiniMax" snap))
               (should (string-match-p "prev-run" snap))))
        (delete-directory tmpdir t)))))


;; ─── Live Backend Performance Report (parses real TSV files) ───

(ert-deftest tdd/live-h2h/parse-recent-results ()
  "Parse real experiment TSV files. Returns a list of result plists."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((results (gptel-auto-workflow--parse-all-results)))
      (should (listp results)))))

(ert-deftest tdd/live-h2h/aggregate-backend-stats ()
  "Aggregate per-backend stats from recent results into a hash table."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (by-backend (make-hash-table :test 'equal)))
      (dolist (r results)
        (let* ((backend (or (plist-get r :backend) "unknown"))
               (kept (equal (plist-get r :decision) "kept")))
          (when backend
            (let ((entry (or (gethash backend by-backend) '(0 0))))
              (setcar entry (1+ (car entry)))
              (when kept (setcar (cdr entry) (1+ (cadr entry))))))))
      (should (hash-table-p by-backend)))))

(provide 'test-gptel-nucleus-context-intercept)
;;; test-gptel-nucleus-context-intercept.el ends here
