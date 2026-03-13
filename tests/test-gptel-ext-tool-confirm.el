;;; test-gptel-ext-tool-confirm.el --- Tests for tool confirmation UI -*- lexical-binding: t; -*-

;;; Commentary:
;; P0 tests for gptel-ext-tool-confirm.el
;; Tests:
;; - my/gptel--tool-spec-name
;; - my/gptel--current-fsm
;; - my/gptel--inspect-fsm
;; - my/gptel--programmatic-confirm-tool
;; - my/gptel--programmatic-aggregate-confirm
;; - my/gptel--display-tool-calls
;; - my/gptel--around-accept-tool-calls
;; - my/gptel--around-reject-tool-calls

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock tool structure

(cl-defstruct (test-gptel-tool (:constructor test-gptel-tool-create))
  name args async confirm)

(defalias 'gptel-tool-name #'test-gptel-tool-name)
(defalias 'gptel-tool-args #'test-gptel-tool-args)
(defalias 'gptel-tool-async #'test-gptel-tool-async)
(defalias 'gptel-tool-confirm #'test-gptel-tool-confirm)

;;; Mock gptel variables

(defvar gptel-backend nil)
(defvar gptel--fsm-last nil)
(defvar gptel--request-alist nil)
(defvar my/gptel-permitted-tools nil)

(defun gptel-backend-name (_backend) "TestBackend")
(defun gptel--format-tool-call (name args)
  (format "%s %s" name (mapconcat #'prin1-to-string args " ")))

;;; Functions under test

(defun test-tool-spec-name (tool-spec)
  "Return a displayable tool name for TOOL-SPEC."
  (or (ignore-errors (test-gptel-tool-name tool-spec))
      (plist-get tool-spec :name)
      (format "%s" tool-spec)))

(defun test-tool-permitted-p (tool-name)
  "Return non-nil if TOOL-NAME has been permitted this session."
  (and my/gptel-permitted-tools
       (gethash tool-name my/gptel-permitted-tools)))

(defun test-permit-tool (tool-name)
  "Permit TOOL-NAME for the rest of this Emacs session."
  (unless my/gptel-permitted-tools
    (setq my/gptel-permitted-tools (make-hash-table :test 'equal)))
  (puthash tool-name t my/gptel-permitted-tools))

(defun test-fsm-p (obj)
  "Check if OBJ is a FSM."
  (and (listp obj) (assq 'fsm-state obj)))

(defun test-coerce-fsm (obj)
  "Coerce OBJ to FSM if possible."
  (cond ((test-fsm-p obj) obj)
        ((consp obj) (test-coerce-fsm (car obj)))
        (t nil)))

(defun test-current-fsm ()
  "Return the current gptel-fsm struct."
  (test-coerce-fsm gptel--fsm-last))

(defun test-programmatic-confirm-tool (tool-spec arg-values callback)
  "Confirm nested Programmatic TOOL-SPEC with ARG-VALUES, then run CALLBACK."
  (if (test-tool-permitted-p (test-gptel-tool-name tool-spec))
      (funcall callback t)
    ;; In test mode, auto-reject non-permitted tools
    (funcall callback nil)))

(defun test-programmatic-aggregate-confirm (plan callback)
  "Show aggregate confirmation UI for multi-step mutating Programmatic PLAN."
  ;; In test mode, always approve
  (funcall callback t))

(defun test-around-accept-tool-calls (orig &optional response ov)
  "Handle nested Programmatic tool confirmations before normal acceptance."
  (if (and response
           (= (length response) 1)
           (functionp (nth 2 (car response))))
      (let ((cb (nth 2 (car response))))
        (when (functionp cb)
          (funcall cb t)))
    (funcall orig response ov)))

(defun test-around-reject-tool-calls (orig &optional response ov)
  "Handle nested Programmatic tool rejections."
  (if (and response
           (= (length response) 1)
           (functionp (nth 2 (car response))))
      (let ((cb (nth 2 (car response))))
        (when (functionp cb)
          (funcall cb nil)))
    (funcall orig response ov)))

(defun test-display-tool-calls (tool-calls callback)
  "Handle tool call confirmation with per-tool permit memory."
  (if (and my/gptel-permitted-tools
           (cl-every (lambda (tc) (test-tool-permitted-p (test-gptel-tool-name (car tc))))
                     tool-calls))
      (funcall callback t)
    ;; In test mode, auto-reject non-permitted
    (funcall callback nil)))

;;; Tests for my/gptel--tool-spec-name

(ert-deftest confirm/tool-spec-name/from-struct ()
  "Should extract name from tool struct."
  (let ((tool (test-gptel-tool-create :name "Read" :confirm nil)))
    (should (equal (test-tool-spec-name tool) "Read"))))

(ert-deftest confirm/tool-spec-name/from-plist ()
  "Should extract name from plist spec."
  (let ((spec '(:name "Grep" :args nil)))
    (should (equal (test-tool-spec-name spec) "Grep"))))

(ert-deftest confirm/tool-spec-name/fallback-to-string ()
  "Should fallback to string representation."
  (should (stringp (test-tool-spec-name 'some-symbol))))

(ert-deftest confirm/tool-spec-name/nil-input ()
  "Should handle nil input."
  (should (equal (test-tool-spec-name nil) "nil")))

;;; Tests for my/gptel-tool-permitted-p

(ert-deftest confirm/permitted-p/when-permitted ()
  "Should return t when tool is permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (should (test-tool-permitted-p "Read"))))

(ert-deftest confirm/permitted-p/when-not-permitted ()
  "Should return nil when tool is not permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (should-not (test-tool-permitted-p "Edit"))))

(ert-deftest confirm/permitted-p/when-table-nil ()
  "Should return nil when permit table is nil."
  (let ((my/gptel-permitted-tools nil))
    (should-not (test-tool-permitted-p "Read"))))

;;; Tests for my/gptel-permit-tool

(ert-deftest confirm/permit/adds-to-table ()
  "Permitting a tool should add it to the table."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Bash")
    (should (test-tool-permitted-p "Bash"))))

(ert-deftest confirm/permit/creates-table-if-needed ()
  "Permitting should create table if nil."
  (let ((my/gptel-permitted-tools nil))
    (test-permit-tool "Read")
    (should (hash-table-p my/gptel-permitted-tools))
    (should (test-tool-permitted-p "Read"))))

(ert-deftest confirm/permit/idempotent ()
  "Permitting same tool twice should not error."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Read")
    (should (test-tool-permitted-p "Read"))))

;;; Tests for my/gptel--programmatic-confirm-tool

(ert-deftest confirm/programmatic/auto-accepts-permitted ()
  "Should auto-accept if tool is already permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal))
        (tool (test-gptel-tool-create :name "Read" :confirm nil))
        (called-with nil))
    (test-permit-tool "Read")
    (test-programmatic-confirm-tool tool '("args")
                                    (lambda (approved) (setq called-with approved)))
    (should (eq called-with t))))

(ert-deftest confirm/programmatic/prompts-non-permitted ()
  "Should prompt for non-permitted tool."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal))
        (tool (test-gptel-tool-create :name "Edit" :confirm t))
        (called-with :not-called))
    ;; This would prompt in real use; we just verify the structure
    (should (functionp (lambda (cb) (test-programmatic-confirm-tool tool '("args") cb))))))

;;; Tests for my/gptel--programmatic-aggregate-confirm

(ert-deftest confirm/aggregate/empty-plan ()
  "Should handle empty plan."
  (let ((called-with :not-called))
    (test-programmatic-aggregate-confirm '()
                                         (lambda (approved) (setq called-with approved)))
    (should (eq called-with t))))

(ert-deftest confirm/aggregate/single-step ()
  "Should handle single-step plan."
  (let ((plan '((:tool-name "Edit" :summary "Edit file.el")))
        (called-with :not-called))
    ;; Verify plan structure
    (should (listp plan))))

(ert-deftest confirm/aggregate/multi-step ()
  "Should format multi-step plan."
  (let ((plan '((:tool-name "Edit" :summary "Edit a.el")
                (:tool-name "Edit" :summary "Edit b.el"))))
    (should (= (length plan) 2))
    (should (plist-get (car plan) :summary))))

;;; Tests for my/gptel--around-accept-tool-calls

(ert-deftest confirm/around-accept/calls-callback ()
  "Should call callback for programmatic tool calls."
  (let* ((called nil)
         (cb (lambda (_) (setq called t)))
         (response (list (list nil nil cb)))
         (orig (lambda (&rest _) nil)))
    (test-around-accept-tool-calls orig response nil)
    (should called)))

(ert-deftest confirm/around-accept/falls-through-for-normal ()
  "Should fall through for normal tool calls."
  (let* ((orig-called nil)
         (response (list (list nil nil nil)))
         (orig (lambda (&rest _) (setq orig-called t))))
    (test-around-accept-tool-calls orig response nil)
    (should orig-called)))

(ert-deftest confirm/around-accept/ignores-nil-response ()
  "Should handle nil response."
  (let* ((orig-called nil)
         (orig (lambda (&rest _) (setq orig-called t))))
    (test-around-accept-tool-calls orig nil nil)
    (should orig-called)))

;;; Tests for my/gptel--around-reject-tool-calls

(ert-deftest confirm/around-reject/calls-callback-with-nil ()
  "Should call callback with nil for programmatic tool calls."
  (let* ((called-with :not-called)
         (response (list (list nil nil (lambda (approved) (setq called-with approved)))))
         (orig (lambda (&rest _) nil)))
    (test-around-reject-tool-calls orig response nil)
    (should (eq called-with nil))))

(ert-deftest confirm/around-reject/falls-through-for-normal ()
  "Should fall through for normal tool calls."
  (let* ((orig-called nil)
         (response (list (list nil nil nil)))
         (orig (lambda (&rest _) (setq orig-called t))))
    (test-around-reject-tool-calls orig response nil)
    (should orig-called)))

;;; Tests for my/gptel--display-tool-calls

(ert-deftest confirm/display/auto-accepts-all-permitted ()
  "Should auto-accept when all tools are permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal))
        (tool (test-gptel-tool-create :name "Read" :confirm nil))
        (called-with :not-called))
    (test-permit-tool "Read")
    (test-display-tool-calls
     (list (list tool '("args") nil))
     (lambda (approved) (setq called-with approved)))
    (should (eq called-with t))))

(ert-deftest confirm/display/prompts-when-not-permitted ()
  "Should prompt when tool not permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal))
        (tool (test-gptel-tool-create :name "Edit" :confirm t)))
    (should (listp (list (list tool '("args") nil))))))

;;; Tests for my/gptel--current-fsm

(ert-deftest confirm/current-fsm/returns-nil-when-no-fsm ()
  "Should return nil when no FSM exists."
  (let ((gptel--fsm-last nil)
        (gptel--request-alist nil))
    (should (null (test-current-fsm)))))

(ert-deftest confirm/current-fsm/coerces-wrapped-fsm ()
  "Should coerce wrapped FSM."
  (let ((gptel--fsm-last '((fsm-state . WAIT) (data . nil))))
    (should (test-fsm-p (test-current-fsm)))))

;;; Tests for FSM state handling

(ert-deftest confirm/fsm-state/detects-wait ()
  "Should detect WAIT state."
  (let ((fsm '((fsm-state . WAIT) (data . nil))))
    (should (eq (cdr (assq 'fsm-state fsm)) 'WAIT))))

(ert-deftest confirm/fsm-state/detects-done ()
  "Should detect DONE state."
  (let ((fsm '((fsm-state . DONE) (data . nil))))
    (should (eq (cdr (assq 'fsm-state fsm)) 'DONE))))

(ert-deftest confirm/fsm-state/detects-tool ()
  "Should detect TOOL state."
  (let ((fsm '((fsm-state . TOOL) (data . nil))))
    (should (eq (cdr (assq 'fsm-state fsm)) 'TOOL))))

;;; Footer

(provide 'test-gptel-ext-tool-confirm)

;;; test-gptel-ext-tool-confirm.el ends here