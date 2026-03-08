;;; gptel-programmatic-benchmark.el --- Benchmark Programmatic orchestration -*- lexical-binding: t; -*-

(require 'benchmark)
(require 'cl-lib)
(require 'subr-x)

(require 'gptel-sandbox)

(cl-defstruct (gptel-programmatic-benchmark-tool
               (:constructor gptel-programmatic-benchmark-tool-create))
  name function args async confirm)

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
          :confirm nil))))

(defconst gptel-programmatic-benchmark--program
  (mapconcat
   #'identity
   '("(setq hits (tool-call \"Grep\" :regex \"Programmatic\" :path \"lisp/modules\"))"
     "(setq first (tool-call \"Read\" :file_path \"lisp/modules/gptel-sandbox.el\" :start_line 1 :end_line 60))"
     "(setq second (tool-call \"Read\" :file_path \"assistant/prompts/code_agent.md\" :start_line 1 :end_line 40))"
     "(result (list :hits hits :first first :second second))")
   "\n")
  "Representative multi-step Programmatic workflow.")

(defun gptel-programmatic-benchmark--run-normal-workflow ()
  "Run the representative workflow without Programmatic orchestration."
  (let* ((grep-tool (gptel-get-tool "Grep"))
         (read-tool (gptel-get-tool "Read"))
         (hits (apply (gptel-tool-function grep-tool)
                      '("Programmatic" "lisp/modules" nil nil)))
         (first (apply (gptel-tool-function read-tool)
                       '("lisp/modules/gptel-sandbox.el" 1 60)))
         (second (apply (gptel-tool-function read-tool)
                        '("assistant/prompts/code_agent.md" 1 40))))
    (list :hits hits :first first :second second)))

(defun gptel-programmatic-benchmark--run-programmatic-workflow ()
  "Run the representative workflow through the Programmatic sandbox."
  (let ((result :pending))
    (gptel-sandbox-execute-async (lambda (value) (setq result value))
                                 gptel-programmatic-benchmark--program)
    (while (eq result :pending)
      (sleep-for 0.0005))
    result))

(defun gptel-programmatic-benchmark--normal-transcript ()
  "Return a representative normal multi-tool transcript string."
  (let* ((result (gptel-programmatic-benchmark--run-normal-workflow))
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

(defun gptel-programmatic-benchmark--programmatic-transcript ()
  "Return a representative Programmatic transcript string."
  (mapconcat
   #'identity
   (list
    (format "assistant: tool_use Programmatic(code=%S)"
            gptel-programmatic-benchmark--program)
    (format "tool_result: %s"
            (gptel-programmatic-benchmark--run-programmatic-workflow)))
   "\n"))

(defun gptel-programmatic-benchmark-run (&optional iterations)
  "Run Programmatic benchmark report for ITERATIONS.
Returns a plist with local timing, simulated end-to-end timing, and transcript
size comparisons."
  (let* ((iterations (or iterations my/gptel-programmatic-benchmark-iterations))
         (gptel-programmatic-benchmark--tools
          (gptel-programmatic-benchmark--make-tools))
         (my/gptel-programmatic-allowed-tools '("Grep" "Read"))
         (my/gptel-programmatic-max-tool-calls 10)
         (my/gptel-programmatic-timeout 5)
         (my/gptel-programmatic-result-limit 10000))
    (gptel-programmatic-benchmark--with-stubs
     (lambda ()
       (let* ((normal-local (car (benchmark-run iterations
                                  (gptel-programmatic-benchmark--run-normal-workflow))))
              (programmatic-local (car (benchmark-run iterations
                                       (gptel-programmatic-benchmark--run-programmatic-workflow))))
              (normal-bytes (string-bytes (gptel-programmatic-benchmark--normal-transcript)))
              (programmatic-bytes
               (string-bytes (gptel-programmatic-benchmark--programmatic-transcript)))
              (turn-latency my/gptel-programmatic-benchmark-simulated-turn-seconds)
              (normal-turns 3)
              (programmatic-turns 1)
              (normal-simulated (+ normal-local (* iterations normal-turns turn-latency)))
              (programmatic-simulated
               (+ programmatic-local (* iterations programmatic-turns turn-latency))))
         (list :workflow "grep-read-read-summarize"
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
               (/ normal-simulated programmatic-simulated)))))))

(defun gptel-programmatic-benchmark-format-report (&optional iterations)
  "Format a human-readable benchmark report for ITERATIONS."
  (pcase-let* ((report (gptel-programmatic-benchmark-run iterations))
               (`(:workflow ,workflow
                  :iterations ,count
                  :normal-local-seconds ,normal-local
                  :programmatic-local-seconds ,programmatic-local
                  :normal-simulated-seconds ,normal-simulated
                  :programmatic-simulated-seconds ,programmatic-simulated
                  :normal-transcript-bytes ,normal-bytes
                  :programmatic-transcript-bytes ,programmatic-bytes
                  :normal-tool-round-trips ,normal-turns
                  :programmatic-tool-round-trips ,programmatic-turns
                  :transcript-byte-reduction ,byte-reduction
                  :simulated-speedup ,speedup) report))
    (format
     (concat
      "Programmatic benchmark\n"
      "workflow: %s\n"
      "iterations: %d\n"
      "local seconds: normal=%.6f programmatic=%.6f\n"
      "simulated end-to-end seconds: normal=%.6f programmatic=%.6f\n"
      "tool round trips: normal=%d programmatic=%d\n"
      "transcript bytes: normal=%d programmatic=%d\n"
      "transcript byte reduction: %.2f%%\n"
      "simulated speedup: %.2fx\n")
     workflow count normal-local programmatic-local
     normal-simulated programmatic-simulated
     normal-turns programmatic-turns
     normal-bytes programmatic-bytes
     (* 100.0 byte-reduction)
     speedup)))

(defun gptel-programmatic-benchmark-print-report (&optional iterations)
  "Print benchmark report for ITERATIONS in batch or interactive sessions."
  (interactive)
  (princ (gptel-programmatic-benchmark-format-report iterations)))

(provide 'gptel-programmatic-benchmark)

;;; gptel-programmatic-benchmark.el ends here
