;;; gptel-programmatic-benchmark.el --- Benchmark Programmatic orchestration -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'benchmark)
(require 'cl-lib)
(require 'subr-x)

(require 'gptel-sandbox)

(cl-defstruct (gptel-programmatic-benchmark-tool
               (:constructor gptel-programmatic-benchmark-tool-create))
  name function args async confirm)

(cl-defstruct (gptel-programmatic-benchmark-workflow
               (:constructor gptel-programmatic-benchmark-workflow-create))
  name
  description
  normal-runner
  programmatic-runner
  normal-transcript
  programmatic-transcript
  normal-turns
  programmatic-turns)

(defcustom my/gptel-programmatic-benchmark-iterations 200
  "Default iteration count for Programmatic benchmark runs."
  :type 'integer
  :group 'gptel-sandbox)

(defcustom my/gptel-programmatic-benchmark-simulated-turn-seconds 0.15
  "Simulated per-turn model latency added to benchmark reports.
This keeps the benchmark honest about what Programmatic optimizes: reducing
tool round trips and transcript chatter, not necessarily raw local CPU time."
  :type 'number
  :group 'gptel-sandbox)

(defvar gptel-programmatic-benchmark--tools nil)

(defun gptel-programmatic-benchmark--tool-name (tool)
  "Return TOOL name."
  (gptel-programmatic-benchmark-tool-name tool))

(defun gptel-programmatic-benchmark--tool-function (tool)
  "Return TOOL function."
  (gptel-programmatic-benchmark-tool-function tool))

(defun gptel-programmatic-benchmark--tool-args (tool)
  "Return TOOL args."
  (gptel-programmatic-benchmark-tool-args tool))

(defun gptel-programmatic-benchmark--tool-async (tool)
  "Return TOOL async flag."
  (gptel-programmatic-benchmark-tool-async tool))

(defun gptel-programmatic-benchmark--tool-confirm (tool)
  "Return TOOL confirm flag."
  (gptel-programmatic-benchmark-tool-confirm tool))

(defun gptel-programmatic-benchmark--to-string (value)
  "Convert VALUE to string."
  (cond
   ((stringp value) value)
   ((null value) "")
   (t (format "%s" value))))

(defun gptel-programmatic-benchmark--get-tool (name)
  "Return benchmark tool by NAME."
  (cdr (assoc name gptel-programmatic-benchmark--tools)))

(defun gptel-programmatic-benchmark--with-stubs (fn)
  "Run FN with gptel sandbox accessors rebound to benchmark stubs."
  (cl-letf (((symbol-function 'gptel-get-tool)
             #'gptel-programmatic-benchmark--get-tool)
            ((symbol-function 'gptel-tool-name)
             #'gptel-programmatic-benchmark--tool-name)
            ((symbol-function 'gptel-tool-function)
             #'gptel-programmatic-benchmark--tool-function)
            ((symbol-function 'gptel-tool-args)
             #'gptel-programmatic-benchmark--tool-args)
            ((symbol-function 'gptel-tool-async)
             #'gptel-programmatic-benchmark--tool-async)
            ((symbol-function 'gptel-tool-confirm)
             #'gptel-programmatic-benchmark--tool-confirm)
            ((symbol-function 'gptel--to-string)
             #'gptel-programmatic-benchmark--to-string))
    (funcall fn)))

(defun gptel-programmatic-benchmark--make-patch (before after)
  "Return a tiny unified diff replacing BEFORE with AFTER."
  (format
   (concat
    "--- a/foo.el\n"
    "+++ b/foo.el\n"
    "@@ -10,1 +10,1 @@\n"
    "-%s\n"
    "+%s\n")
   before after))

(defun gptel-programmatic-benchmark--make-tools ()
  "Create the benchmark tool registry."
  (list
   (cons "Grep"
         (gptel-programmatic-benchmark-tool-create
          :name "Grep"
          :function (lambda (regex path &optional _glob _context-lines)
                      (format "%s:%s:%s\n%s:%s:%s"
                              path 12 regex
                              path 34 regex))
          :args '((:name "regex")
                  (:name "path")
                  (:name "glob" :optional t)
                  (:name "context_lines" :optional t))
          :async nil
          :confirm nil))
   (cons "Read"
         (gptel-programmatic-benchmark-tool-create
          :name "Read"
          :function (lambda (file-path &optional start-line end-line)
                      (format "%s:%s:%s => %s"
                              file-path start-line end-line
                              (make-string 80 ?x)))
          :args '((:name "file_path")
                  (:name "start_line" :optional t)
                  (:name "end_line" :optional t))
          :async nil
          :confirm nil))
(cons "Edit"
          (gptel-programmatic-benchmark-tool-create
           :name "Edit"
           :function (lambda (file_path &optional old_str new_str diffp)
                       (let* ((payload (or new_str ""))
                              (digest (substring payload 0 (min 48 (length payload)))))
                         (format "edited:%s:%s:%s:%s"
                                 file_path
                                 (if diffp "diff" "text")
                                 (or old_str "nil")
                                 digest)))
           :args '((:name "file_path")
                   (:name "old_str" :optional t)
                   (:name "new_str")
                   (:name "diffp" :optional t))
           :async nil
           :confirm t))))

(defconst gptel-programmatic-benchmark--read-only-program
  (mapconcat
   #'identity
   '("(setq hits (tool-call \"Grep\" :regex \"Programmatic\" :path \"lisp/modules\"))"
     "(setq first (tool-call \"Read\" :file_path \"lisp/modules/gptel-sandbox.el\" :start_line 1 :end_line 60))"
     "(setq second (tool-call \"Read\" :file_path \"assistant/prompts/code_agent.md\" :start_line 1 :end_line 40))"
     "(result (list :hits hits :first first :second second))")
   "\n")
  "Representative read-only Programmatic workflow.")

(defconst gptel-programmatic-benchmark--mutating-program
  (mapconcat
   #'identity
   '("(setq original (tool-call \"Read\" :file_path \"foo.el\" :start_line 1 :end_line 20))"
     "(setq patch \"--- a/foo.el\n+++ b/foo.el\n@@ -10,1 +10,1 @@\n-old-value\n+new-value\n\")"
     "(setq edit-result (tool-call \"Edit\" :file_path \"foo.el\" :new_str patch :diffp t))"
     "(result (list :original original :edit edit-result))")
   "\n")
  "Representative preview-backed mutating Programmatic workflow.")

(defun gptel-programmatic-benchmark--run-read-only-normal-workflow ()
  "Run the representative read-only workflow without Programmatic orchestration."
  (let* ((grep-tool (gptel-get-tool "Grep"))
         (read-tool (gptel-get-tool "Read"))
         (hits (apply (gptel-tool-function grep-tool)
                      '("Programmatic" "lisp/modules" nil nil)))
         (first (apply (gptel-tool-function read-tool)
                       '("lisp/modules/gptel-sandbox.el" 1 60)))
         (second (apply (gptel-tool-function read-tool)
                        '("assistant/prompts/code_agent.md" 1 40))))
    (list :hits hits :first first :second second)))

(defun gptel-programmatic-benchmark--run-mutating-normal-workflow ()
  "Run the representative preview-backed mutating workflow without Programmatic."
  (let* ((read-tool (gptel-get-tool "Read"))
         (edit-tool (gptel-get-tool "Edit"))
         (original (apply (gptel-tool-function read-tool)
                          '("foo.el" 1 20)))
         (patch (gptel-programmatic-benchmark--make-patch "old-value" "new-value"))
         (edit-result (apply (gptel-tool-function edit-tool)
                             (list "foo.el" nil patch t))))
    (list :original original :edit edit-result)))

(defun gptel-programmatic-benchmark--run-programmatic-workflow (program)
  "Run PROGRAM through the Programmatic sandbox."
  (let ((result :pending))
    (gptel-sandbox-execute-async (lambda (value) (setq result value)) program)
    (while (eq result :pending)
      (sleep-for 0.0005))
    result))

(defun gptel-programmatic-benchmark--read-only-programmatic-workflow ()
  "Run the representative read-only workflow through Programmatic."
  (gptel-programmatic-benchmark--run-programmatic-workflow
   gptel-programmatic-benchmark--read-only-program))

(defun gptel-programmatic-benchmark--mutating-programmatic-workflow ()
  "Run the representative preview-backed mutating workflow through Programmatic."
  (gptel-programmatic-benchmark--run-programmatic-workflow
   gptel-programmatic-benchmark--mutating-program))

(defun gptel-programmatic-benchmark--read-only-normal-transcript ()
  "Return a representative ordinary multi-tool transcript string."
  (let* ((result (gptel-programmatic-benchmark--run-read-only-normal-workflow))
         (hits (plist-get result :hits))
         (first (plist-get result :first))
         (second (plist-get result :second)))
    (mapconcat
     #'identity
     (list
      "assistant: tool_use Grep(regex=Programmatic path=lisp/modules)"
      (format "tool_result: %s" hits)
      "assistant: tool_use Read(file_path=lisp/modules/gptel-sandbox.el start_line=1 end_line=60)"
      (format "tool_result: %s" first)
      "assistant: tool_use Read(file_path=assistant/prompts/code_agent.md start_line=1 end_line=40)"
      (format "tool_result: %s" second)
      (format "assistant: final %S" result))
     "\n")))

(defun gptel-programmatic-benchmark--mutating-normal-transcript ()
  "Return a representative ordinary preview-backed mutating transcript."
  (let* ((result (gptel-programmatic-benchmark--run-mutating-normal-workflow))
         (original (plist-get result :original))
         (edit-result (plist-get result :edit))
         (patch (gptel-programmatic-benchmark--make-patch "old-value" "new-value")))
    (mapconcat
     #'identity
     (list
      "assistant: tool_use Read(file_path=foo.el start_line=1 end_line=20)"
      (format "tool_result: %s" original)
      (format "assistant: tool_use Edit(path=foo.el diff=%S)" patch)
      "tool_confirmation: preview-backed edit confirmed"
      (format "tool_result: %s" edit-result)
      (format "assistant: final %S" result))
     "\n")))

(defun gptel-programmatic-benchmark--programmatic-transcript (program runner)
  "Return a representative Programmatic transcript for PROGRAM using RUNNER."
  (mapconcat
   #'identity
   (list
    (format "assistant: tool_use Programmatic(code=%S)" program)
    (format "tool_result: %s" (funcall runner)))
   "\n"))

(defun gptel-programmatic-benchmark--make-workflows ()
  "Return benchmark workflow definitions."
  (list
   (gptel-programmatic-benchmark-workflow-create
    :name "grep-read-read-summarize"
    :description "Read-only orchestration"
    :normal-runner #'gptel-programmatic-benchmark--run-read-only-normal-workflow
    :programmatic-runner #'gptel-programmatic-benchmark--read-only-programmatic-workflow
    :normal-transcript #'gptel-programmatic-benchmark--read-only-normal-transcript
    :programmatic-transcript
    (lambda ()
      (gptel-programmatic-benchmark--programmatic-transcript
       gptel-programmatic-benchmark--read-only-program
       #'gptel-programmatic-benchmark--read-only-programmatic-workflow))
    :normal-turns 3
    :programmatic-turns 1)
   (gptel-programmatic-benchmark-workflow-create
    :name "read-edit-diff"
    :description "Preview-backed mutating orchestration"
    :normal-runner #'gptel-programmatic-benchmark--run-mutating-normal-workflow
    :programmatic-runner #'gptel-programmatic-benchmark--mutating-programmatic-workflow
    :normal-transcript #'gptel-programmatic-benchmark--mutating-normal-transcript
    :programmatic-transcript
    (lambda ()
      (gptel-programmatic-benchmark--programmatic-transcript
       gptel-programmatic-benchmark--mutating-program
       #'gptel-programmatic-benchmark--mutating-programmatic-workflow))
    :normal-turns 2
    :programmatic-turns 1)))

(defun gptel-programmatic-benchmark--measure-workflow (workflow iterations)
  "Measure WORKFLOW for ITERATIONS and return a report plist."
  (let* ((normal-runner (gptel-programmatic-benchmark-workflow-normal-runner workflow))
         (programmatic-runner
          (gptel-programmatic-benchmark-workflow-programmatic-runner workflow))
         (normal-local (car (benchmark-run iterations (funcall normal-runner))))
         (programmatic-local (car (benchmark-run iterations (funcall programmatic-runner))))
         (normal-bytes
          (string-bytes (funcall (gptel-programmatic-benchmark-workflow-normal-transcript workflow))))
         (programmatic-bytes
          (string-bytes
           (funcall (gptel-programmatic-benchmark-workflow-programmatic-transcript workflow))))
         (turn-latency my/gptel-programmatic-benchmark-simulated-turn-seconds)
         (normal-turns (gptel-programmatic-benchmark-workflow-normal-turns workflow))
         (programmatic-turns
          (gptel-programmatic-benchmark-workflow-programmatic-turns workflow))
         (normal-simulated (+ normal-local (* iterations normal-turns turn-latency)))
         (programmatic-simulated
          (+ programmatic-local (* iterations programmatic-turns turn-latency))))
    (list :workflow (gptel-programmatic-benchmark-workflow-name workflow)
          :description (gptel-programmatic-benchmark-workflow-description workflow)
          :iterations iterations
          :normal-local-seconds normal-local
          :programmatic-local-seconds programmatic-local
          :normal-simulated-seconds normal-simulated
          :programmatic-simulated-seconds programmatic-simulated
          :normal-transcript-bytes normal-bytes
          :programmatic-transcript-bytes programmatic-bytes
          :normal-tool-round-trips normal-turns
          :programmatic-tool-round-trips programmatic-turns
          :transcript-byte-reduction
          (- 1.0 (/ (float programmatic-bytes) normal-bytes))
          :simulated-speedup
          (/ normal-simulated programmatic-simulated))))

(defun gptel-programmatic-benchmark-run (&optional iterations)
  "Run Programmatic benchmark report for ITERATIONS.
Returns a plist containing per-workflow reports for read-only and mutating
preview-backed flows."
  (let* ((iterations (or iterations my/gptel-programmatic-benchmark-iterations))
         (gptel-programmatic-benchmark--tools
          (gptel-programmatic-benchmark--make-tools))
         (my/gptel-programmatic-allowed-tools '("Grep" "Read" "Edit"))
         (my/gptel-programmatic-readonly-tools '("Grep" "Read"))
         (my/gptel-programmatic-confirming-tools '("Edit"))
         (my/gptel-programmatic-max-tool-calls 10)
         (my/gptel-programmatic-timeout 5)
         (my/gptel-programmatic-result-limit 10000)
         (gptel-confirm-tool-calls t)
         (gptel-sandbox-confirm-function
          (lambda (_tool-spec _arg-values callback)
            (funcall callback t))))
    (gptel-programmatic-benchmark--with-stubs
     (lambda ()
       (list :iterations iterations
             :workflows
             (mapcar (lambda (workflow)
                       (gptel-programmatic-benchmark--measure-workflow workflow iterations))
                     (gptel-programmatic-benchmark--make-workflows)))))))

(defun gptel-programmatic-benchmark-format-report (&optional iterations)
  "Format a human-readable benchmark report for ITERATIONS."
  (let* ((report (gptel-programmatic-benchmark-run iterations))
         (count (plist-get report :iterations))
         (workflows (plist-get report :workflows)))
    (concat
     (format "Programmatic benchmark suite\niterations: %d\n\n" count)
     (mapconcat
     (lambda (workflow)
        (let ((name (plist-get workflow :workflow))
              (description (plist-get workflow :description))
              (normal-local (plist-get workflow :normal-local-seconds))
              (programmatic-local (plist-get workflow :programmatic-local-seconds))
              (normal-simulated (plist-get workflow :normal-simulated-seconds))
              (programmatic-simulated (plist-get workflow :programmatic-simulated-seconds))
              (normal-bytes (plist-get workflow :normal-transcript-bytes))
              (programmatic-bytes (plist-get workflow :programmatic-transcript-bytes))
              (normal-turns (plist-get workflow :normal-tool-round-trips))
              (programmatic-turns (plist-get workflow :programmatic-tool-round-trips))
              (byte-reduction (plist-get workflow :transcript-byte-reduction))
              (speedup (plist-get workflow :simulated-speedup)))
          (format
           (concat
            "workflow: %s\n"
            "description: %s\n"
            "local seconds: normal=%.6f programmatic=%.6f\n"
            "simulated end-to-end seconds: normal=%.6f programmatic=%.6f\n"
            "tool round trips: normal=%d programmatic=%d\n"
            "transcript bytes: normal=%d programmatic=%d\n"
            "transcript byte reduction: %.2f%%\n"
            "simulated speedup: %.2fx\n")
           name description normal-local programmatic-local
           normal-simulated programmatic-simulated
           normal-turns programmatic-turns
           normal-bytes programmatic-bytes
           (* 100.0 byte-reduction)
           speedup)))
      workflows
      "\n"))))

(defun gptel-programmatic-benchmark-print-report (&optional iterations)
  "Print benchmark report for ITERATIONS in batch or interactive sessions."
  (interactive)
  (princ (gptel-programmatic-benchmark-format-report iterations)))

(provide 'gptel-programmatic-benchmark)

;;; gptel-programmatic-benchmark.el ends here
