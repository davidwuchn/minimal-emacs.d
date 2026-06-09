;;; gptel-ext-circuit-breaker.el --- Circuit breaker for resilient failure management -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Circuit breaker pattern for gptel auto-workflow components.
;; Prevents cascading failures by temporarily disabling degraded components.
;;
;; Three states:
;;   CLOSED  → Normal operation; failures tracked
;;   OPEN    → Component disabled; fast-fail all requests
;;   HALF-OPEN → Testing recovery with one probe request
;;
;; State is persisted to disk so Open → Half-Open transitions survive daemon restarts.
;; Each component (researcher, analyzer, executor, grader) has independent circuit.
;;
;; ASSUMPTION: Components are independent enough that one circuit opening
;;   does not cascade to others (each is called in isolation).
;;
;; ASSUMPTION: Circuit state is advisory — callers check circuit state before
;;   invoking and handle OPEN responses gracefully.
;;
;; EDGE CASE: Daemon restart during OPEN state → re-reads persistent state,
;;   continues from OPEN. Semi-open timer runs on next call (lazy init).
;;
;; WISDOM: Circuit opens quickly (3 failures) to prevent hammering a degraded
;;   provider. Half-open probe after 60s prevents prolonged outages from
;;   blocking useful work.

;;; Code:

(require 'cl-lib)
(require 'json)

(defgroup gptel-circuit-breaker nil
  "Circuit breaker for resilient failure management."
  :group 'gptel)

;;; ─── Circuit State ───

(cl-defstruct (gptel-circuit-breaker
                (:constructor gptel-circuit-breaker-create))
  name                 ; component name (symbol)
  state                ; 'closed, 'open, or 'half-open
  failure-count        ; consecutive failures since last success
  success-count        ; consecutive successes in half-open
  last-failure-time    ; epoch seconds of last failure
  last-failure-msg     ; human-readable last failure reason
  total-failures       ; total failures since load
  total-successes      ; total successes since load
  opened-at            ; epoch seconds when last opened (nil if closed)
  )

(defun gptel-circuit--persist-path ()
  "Return path to circuit-breaker state file."
  (expand-file-name "var/tmp/circuit-breaker-state.json"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (ignore-errors (gptel-auto-workflow--worktree-base-root)))
                      user-emacs-directory)))

(defun gptel-circuit--state-to-plist (cb)
  "Serialize CB circuit-breaker struct to plist for JSON."
  (list :name (symbol-name (gptel-circuit-breaker-name cb))
        :state (symbol-name (gptel-circuit-breaker-state cb))
        :failure-count (gptel-circuit-breaker-failure-count cb)
        :success-count (gptel-circuit-breaker-success-count cb)
        :last-failure-time (or (gptel-circuit-breaker-last-failure-time cb) 0.0)
        :last-failure-msg (or (gptel-circuit-breaker-last-failure-msg cb) "")
        :total-failures (gptel-circuit-breaker-total-failures cb)
        :total-successes (gptel-circuit-breaker-total-successes cb)
         :opened-at (or (gptel-circuit-breaker-opened-at cb) 0.0)))

(defun gptel-circuit--plist-to-state (plist)
  "Deserialize PLIST to a circuit-breaker struct."
  (gptel-circuit-breaker-create
   :name (intern (or (plist-get plist :name) "unknown"))
   :state (intern (or (plist-get plist :state) "closed"))
   :failure-count (or (plist-get plist :failure-count) 0)
   :success-count (or (plist-get plist :success-count) 0)
   :last-failure-time (plist-get plist :last-failure-time)
   :last-failure-msg (plist-get plist :last-failure-msg)
   :total-failures (or (plist-get plist :total-failures) 0)
   :total-successes (or (plist-get plist :total-successes) 0)
   :opened-at (plist-get plist :opened-at)))

(defun gptel-circuit--load-persistent ()
  "Load all circuit-breaker states from disk.
Returns hash table: name symbol → circuit-breaker struct."
  (let ((path (gptel-circuit--persist-path))
        (circuits (make-hash-table :test 'eq)))
    (when (file-exists-p path)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents path)
            (goto-char (point-min))
            (let ((json-object-type 'plist)
                  (json-array-type 'list)
                  (json-key-type 'keyword))
              (let ((data (json-read)))
                (dolist (entry data)
                  (let* ((name-str (plist-get entry :name))
                         (state-plist (plist-get entry :state-data)))
                     (when (and name-str state-plist)
                       (puthash (intern name-str)
                                (gptel-circuit--plist-to-state state-plist)
                                circuits)))))))
        (error
         (message "[circuit-breaker] Failed to load state: %s" err))))
    circuits)))

(defun gptel-circuit--save-persistent (circuits)
  "Persist CIRCUITS hash table to disk.
CIRCUITS: name symbol → circuit-breaker struct."
  (let ((path (gptel-circuit--persist-path)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (let ((data
             (cl-mapcar
              (lambda (name cb)
                (list :name (symbol-name name)
                      :state-data (gptel-circuit--state-to-plist cb)))
              (cl-loop for k being the hash-keys of circuits collect k)
              (cl-loop for v being the hash-values of circuits collect v))))
         (insert (gptel-auto-workflow--json-encode-plist data))))
    (message "[circuit-breaker] State persisted (%d circuits)" (hash-table-count circuits))))

;;; ─── Configuration ───

(defcustom gptel-circuit-breaker-failure-threshold 3
  "Number of consecutive failures before opening circuit.
Default 3 gives fast failure detection without being too sensitive.
Set higher for components with naturally variable responses."
  :type 'integer
  :group 'gptel-circuit-breaker)

(defcustom gptel-circuit-breaker-timeout-seconds 60
  "Seconds before half-open probe attempt.
Default 60s balances quick recovery against not hammering a degraded API.
During OPEN state, calls fast-fail immediately without hitting the provider."
  :type 'integer
  :group 'gptel-circuit-breaker)

(defcustom gptel-circuit-breaker-half-open-successes 1
  "Consecutive successes needed in half-open to close circuit.
Default 1 means one successful probe closes the circuit."
  :type 'integer
  :group 'gptel-circuit-breaker)

(defcustom gptel-circuit-breaker-max-failure-window 300
  "Window in seconds for counting failures in CLOSED state.
Failures older than this window are pruned from the count.
Default 300s (5min) gives a rolling window for failure rate assessment."
  :type 'integer
  :group 'gptel-circuit-breaker)

(defcustom gptel-circuit-breaker-save-throttle 5
  "Minimum seconds between disk saves.
Prevents thrashing disk on rapid failures. Default 5s."
  :type 'integer
  :group 'gptel-circuit-breaker)

;;; ─── Global Circuit Registry ───

(defvar gptel-circuit--circuits (make-hash-table :test 'eq)
  "Hash table: component name (symbol) → circuit-breaker struct.")

(defvar gptel-circuit--last-save-time 0.0
  "Epoch seconds of last disk save.")

(defvar gptel-circuit--init-done nil
  "Non-nil after lazy initialization.")

(defun gptel-circuit--lazy-init ()
  "Lazily initialize circuit registry from disk."
  (unless gptel-circuit--init-done
    (setq gptel-circuit--circuits (gptel-circuit--load-persistent))
    (setq gptel-circuit--init-done t)
    ;; Auto-register known components
    (dolist (component '(researcher analyzer executor grader))
      (gptel-circuit-get component))))

(defun gptel-circuit--save-if-throttled ()
  "Save state to disk if throttle allows."
  (let ((now (float-time)))
    (when (>= (- now gptel-circuit--last-save-time)
              gptel-circuit-breaker-save-throttle)
      (gptel-circuit--save-persistent gptel-circuit--circuits)
      (setq gptel-circuit--last-save-time now))))

;;; ─── Public API ───

(defun gptel-circuit-get (component)
  "Get or create circuit-breaker for COMPONENT (symbol).
Creates CLOSED circuit if not yet registered.
Thread-safe enough for single-threaded Emacs."
  (gptel-circuit--lazy-init)
  (or (gethash component gptel-circuit--circuits)
      (let ((cb (gptel-circuit-breaker-create :name component :state 'closed)))
        (puthash component cb gptel-circuit--circuits)
        cb)))

(defun gptel-circuit-state (component)
  "Return circuit state for COMPONENT: 'closed, 'open, or 'half-open.
Also transitions OPEN → half-open if timeout elapsed."
  (let* ((cb (gptel-circuit-get component))
         (state (gptel-circuit-breaker-state cb)))
    (when (eq state 'open)
      ;; Check if timeout elapsed → transition to half-open
      (let* ((opened-at (gptel-circuit-breaker-opened-at cb))
             (now (float-time)))
        (when (and opened-at
                   (>= (- now opened-at) gptel-circuit-breaker-timeout-seconds))
          (setf (gptel-circuit-breaker-state cb) 'half-open)
          (message "[circuit-breaker] %s: OPEN → HALF-OPEN (timeout elapsed)"
                   component)
          (gptel-circuit--save-if-throttled))))
    (gptel-circuit-breaker-state cb)))

(defun gptel-circuit-allow-p (component)
  "Return non-nil if requests to COMPONENT are allowed.
Checks state and handles OPEN→half-open transition.
In HALF-OPEN state, allows one probe request."
  (gptel-circuit--lazy-init)
  (let ((state (gptel-circuit-state component)))
    (not (eq state 'open))))

(defun gptel-circuit-record-success (component)
  "Record successful operation for COMPONENT.
Closes circuit from half-open; resets failure count from closed.
Returns the new circuit-breaker struct."
  (gptel-circuit--lazy-init)
  (let* ((cb (gptel-circuit-get component))
         (state (gptel-circuit-breaker-state cb)))
    (cl-incf (gptel-circuit-breaker-total-successes cb))
    (cond
     ;; Half-open → close the circuit
     ((eq state 'half-open)
      (setf (gptel-circuit-breaker-state cb) 'closed
            (gptel-circuit-breaker-failure-count cb) 0
            (gptel-circuit-breaker-success-count cb) 0
            (gptel-circuit-breaker-opened-at cb) nil)
      (message "[circuit-breaker] %s: HALF-OPEN → CLOSED (success)"
               component))
     ;; Closed → just reset failure count
     (t
      (setf (gptel-circuit-breaker-failure-count cb) 0
            (gptel-circuit-breaker-success-count cb) 0)))
    (gptel-circuit--save-if-throttled)
    cb))

(defun gptel-circuit-record-failure (component &optional error-msg)
  "Record failed operation for COMPONENT with optional ERROR-MSG.
Opens circuit from closed or half-open when threshold exceeded.
Returns the new circuit-breaker struct."
  (gptel-circuit--lazy-init)
  (let* ((cb (gptel-circuit-get component))
         (now (float-time)))
    (cl-incf (gptel-circuit-breaker-failure-count cb)
             (if (eq (gptel-circuit-breaker-state cb) 'half-open) 2 1))
    (cl-incf (gptel-circuit-breaker-total-failures cb))
    (setf (gptel-circuit-breaker-last-failure-time cb) now
          (gptel-circuit-breaker-last-failure-msg cb)
          (if (stringp error-msg) error-msg "unknown"))
    (let ((state (gptel-circuit-breaker-state cb)))
      (cond
       ;; Half-open → immediately open again (probe failed)
       ((eq state 'half-open)
        (setf (gptel-circuit-breaker-state cb) 'open
              (gptel-circuit-breaker-success-count cb) 0
              (gptel-circuit-breaker-opened-at cb) now)
        (message "[circuit-breaker] %s: HALF-OPEN → OPEN (probe failed: %s)"
                 component
                 (gptel-circuit-breaker-last-failure-msg cb)))
       ;; Closed → check threshold
       ((eq state 'closed)
        (when (>= (gptel-circuit-breaker-failure-count cb)
                  gptel-circuit-breaker-failure-threshold)
          (setf (gptel-circuit-breaker-state cb) 'open
                (gptel-circuit-breaker-opened-at cb) now)
          (message "[circuit-breaker] %s: CLOSED → OPEN (failures=%d >= threshold=%d): %s"
                   component
                   (gptel-circuit-breaker-failure-count cb)
                   gptel-circuit-breaker-failure-threshold
                   (gptel-circuit-breaker-last-failure-msg cb))))))
    (gptel-circuit--save-if-throttled)
    cb))

(defun gptel-circuit-reset (component)
  "Force COMPONENT circuit back to CLOSED state.
Use for manual intervention after resolving root cause."
  (gptel-circuit--lazy-init)
  (let ((cb (gptel-circuit-get component)))
    (setf (gptel-circuit-breaker-state cb) 'closed
          (gptel-circuit-breaker-failure-count cb) 0
          (gptel-circuit-breaker-success-count cb) 0
          (gptel-circuit-breaker-opened-at cb) nil)
    (message "[circuit-breaker] %s: RESET to CLOSED" component)
    (gptel-circuit--save-persistent gptel-circuit--circuits)
    cb))

(defun gptel-circuit-status ()
  "Return status of all circuit-breakers as list of plists."
  (gptel-circuit--lazy-init)
  (cl-loop for name being the hash-keys of gptel-circuit--circuits
           using (hash-values cb)
           collect (list :component name
                         :state (gptel-circuit-state name)
                         :failure-count (gptel-circuit-breaker-failure-count cb)
                         :total-failures (gptel-circuit-breaker-total-failures cb)
                         :total-successes (gptel-circuit-breaker-total-successes cb)
                         :opened-at (gptel-circuit-breaker-opened-at cb)
                         :last-failure-time (gptel-circuit-breaker-last-failure-time cb)
                         :last-failure-msg (gptel-circuit-breaker-last-failure-msg cb))))

(defun gptel-circuit-save ()
  "Force immediate save of circuit state to disk."
  (gptel-circuit--lazy-init)
  (gptel-circuit--save-persistent gptel-circuit--circuits)
  (setq gptel-circuit--last-save-time (float-time)))

;;; ─── Integration Helpers ───

(defmacro gptel-circuit--with-check (component &rest body)
  "Execute BODY only if COMPONENT circuit allows requests.
BODY should return (success . result) where success is non-nil on success.
On circuit OPEN, returns (nil . \"circuit open\") without executing BODY.
On success, records success. On failure, records failure with ERROR-MSG from
BODY."
  (declare (indent 1))
  `(let* ((state (gptel-circuit-state ,component)))
     (if (eq state 'open)
         (progn
           (message "[circuit-breaker] %s: rejecting request (circuit OPEN)" ,component)
           (cons nil (format "circuit open for %s" ,component)))
       (let ((result (progn ,@body)))
         (if (car result)
             (gptel-circuit-record-success ,component)
           (gptel-circuit-record-failure ,component (cdr result)))
         result))))

(provide 'gptel-ext-circuit-breaker)
;;; gptel-ext-circuit-breaker.el ends here
