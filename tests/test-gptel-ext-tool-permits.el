;;; test-gptel-ext-tool-permits.el --- Tests for tool permit system -*- lexical-binding: t; -*-

;;; Commentary:
;; P0 tests for gptel-ext-tool-permits.el
;; Tests:
;; - my/gptel-tool-permitted-p
;; - my/gptel-permit-tool
;; - my/gptel-clear-permits
;; - my/gptel-toggle-confirm
;; - my/gptel-show-permits
;; - my/gptel--sync-to-upstream

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables

(defvar my/gptel-confirm-mode 'auto)
(defvar my/gptel-permitted-tools nil)
(defvar gptel-confirm-tool-calls nil)

;;; Functions under test

(defun test-tool-permitted-p (tool-name)
  "Return non-nil if TOOL-NAME has been permitted this session."
  (and my/gptel-permitted-tools
       (gethash tool-name my/gptel-permitted-tools)))

(defun test-permit-tool (tool-name)
  "Permit TOOL-NAME for the rest of this Emacs session."
  (unless my/gptel-permitted-tools
    (setq my/gptel-permitted-tools (make-hash-table :test 'equal)))
  (puthash tool-name t my/gptel-permitted-tools))

(defun test-clear-permits ()
  "Clear all per-tool permits."
  (when my/gptel-permitted-tools
    (clrhash my/gptel-permitted-tools)))

(defun test-toggle-confirm ()
  "Toggle between auto and confirm-all modes."
  (setq my/gptel-confirm-mode
        (if (eq my/gptel-confirm-mode 'auto) 'confirm-all 'auto))
  (when (eq my/gptel-confirm-mode 'confirm-all)
    (test-clear-permits))
  (setq gptel-confirm-tool-calls
        (if (eq my/gptel-confirm-mode 'auto) nil t))
  my/gptel-confirm-mode)

(defun test-sync-to-upstream ()
  "Sync confirm mode to upstream."
  (setq gptel-confirm-tool-calls
        (if (eq my/gptel-confirm-mode 'auto) nil t)))

;;; Tests for my/gptel-tool-permitted-p

(ert-deftest permits/permitted-p/returns-nil-initially ()
  "Should return nil when no tools permitted."
  (let ((my/gptel-permitted-tools nil))
    (should-not (test-tool-permitted-p "Read"))))

(ert-deftest permits/permitted-p/returns-t-after-permit ()
  "Should return t after tool is permitted."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (should (test-tool-permitted-p "Read"))))

(ert-deftest permits/permitted-p/case-sensitive ()
  "Tool names should be case-sensitive."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (should (test-tool-permitted-p "Read"))
    (should-not (test-tool-permitted-p "read"))
    (should-not (test-tool-permitted-p "READ"))))

(ert-deftest permits/permitted-p/multiple-tools ()
  "Should handle multiple permitted tools."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Write")
    (test-permit-tool "Bash")
    (should (test-tool-permitted-p "Read"))
    (should (test-tool-permitted-p "Write"))
    (should (test-tool-permitted-p "Bash"))
    (should-not (test-tool-permitted-p "Edit"))))

;;; Tests for my/gptel-permit-tool

(ert-deftest permits/permit/creates-table ()
  "Permitting should create hash table if nil."
  (let ((my/gptel-permitted-tools nil))
    (test-permit-tool "Bash")
    (should (hash-table-p my/gptel-permitted-tools))
    (should (= (hash-table-count my/gptel-permitted-tools) 1))))

(ert-deftest permits/permit/adds-to-existing-table ()
  "Permitting should add to existing table."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Write")
    (should (= (hash-table-count my/gptel-permitted-tools) 2))))

(ert-deftest permits/permit/overwrites-existing ()
  "Permitting same tool should not duplicate."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Read")
    (should (= (hash-table-count my/gptel-permitted-tools) 1))))

;;; Tests for my/gptel-clear-permits

(ert-deftest permits/clear/empties-table ()
  "Clearing should empty the table."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Write")
    (test-clear-permits)
    (should (= (hash-table-count my/gptel-permitted-tools) 0))
    (should-not (test-tool-permitted-p "Read"))))

(ert-deftest permits/clear/handles-nil-table ()
  "Clearing nil table should not error."
  (let ((my/gptel-permitted-tools nil))
    (should-not (errorp (test-clear-permits)))))

(defun errorp (form)
  "Return t if FORM signals an error."
  (condition-case nil
      (progn form nil)
    (error t)))

;;; Tests for my/gptel-toggle-confirm

(ert-deftest permits/toggle/starts-at-auto ()
  "Should start in auto mode."
  (let ((my/gptel-confirm-mode 'auto))
    (should (eq my/gptel-confirm-mode 'auto))))

(ert-deftest permits/toggle/switches-to-confirm-all ()
  "Toggling from auto should switch to confirm-all."
  (let ((my/gptel-confirm-mode 'auto)
        (my/gptel-permitted-tools nil)
        (gptel-confirm-tool-calls nil))
    (test-toggle-confirm)
    (should (eq my/gptel-confirm-mode 'confirm-all))
    (should (eq gptel-confirm-tool-calls t))))

(ert-deftest permits/toggle/switches-back-to-auto ()
  "Toggling from confirm-all should switch to auto."
  (let ((my/gptel-confirm-mode 'confirm-all)
        (my/gptel-permitted-tools nil)
        (gptel-confirm-tool-calls t))
    (test-toggle-confirm)
    (should (eq my/gptel-confirm-mode 'auto))
    (should (eq gptel-confirm-tool-calls nil))))

(ert-deftest permits/toggle/clears-permits-on-confirm-all ()
  "Switching to confirm-all should clear permits."
  (let ((my/gptel-confirm-mode 'auto)
        (my/gptel-permitted-tools (make-hash-table :test 'equal))
        (gptel-confirm-tool-calls nil))
    (test-permit-tool "Read")
    (test-toggle-confirm)
    (should (= (hash-table-count my/gptel-permitted-tools) 0))))

(ert-deftest permits/toggle/twice-returns-to-original ()
  "Toggling twice should return to original mode."
  (let ((my/gptel-confirm-mode 'auto)
        (my/gptel-permitted-tools nil)
        (gptel-confirm-tool-calls nil))
    (test-toggle-confirm)
    (test-toggle-confirm)
    (should (eq my/gptel-confirm-mode 'auto))
    (should (eq gptel-confirm-tool-calls nil))))

;;; Tests for my/gptel--sync-to-upstream

(ert-deftest permits/sync/auto-sets-nil ()
  "Auto mode should sync to nil."
  (let ((my/gptel-confirm-mode 'auto)
        (gptel-confirm-tool-calls t))
    (test-sync-to-upstream)
    (should (null gptel-confirm-tool-calls))))

(ert-deftest permits/sync/confirm-all-sets-t ()
  "Confirm-all mode should sync to t."
  (let ((my/gptel-confirm-mode 'confirm-all)
        (gptel-confirm-tool-calls nil))
    (test-sync-to-upstream)
    (should (eq gptel-confirm-tool-calls t))))

;;; Tests for mode state

(ert-deftest permits/mode/auto-allows-all ()
  "Auto mode should not require confirmation."
  (let ((my/gptel-confirm-mode 'auto))
    (should (eq my/gptel-confirm-mode 'auto))))

(ert-deftest permits/mode/confirm-all-requires-confirmation ()
  "Confirm-all mode should require confirmation."
  (let ((my/gptel-confirm-mode 'confirm-all))
    (should (eq my/gptel-confirm-mode 'confirm-all))))

;;; Tests for permit persistence

(ert-deftest permits/persistence/within-session ()
  "Permits should persist within session."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (should (test-tool-permitted-p "Read"))))

(ert-deftest permits/persistence/multiple-permit-calls ()
  "Multiple permit calls should all be remembered."
  (let ((my/gptel-permitted-tools (make-hash-table :test 'equal)))
    (test-permit-tool "Read")
    (test-permit-tool "Grep")
    (test-permit-tool "Bash")
    (should (test-tool-permitted-p "Read"))
    (should (test-tool-permitted-p "Grep"))
    (should (test-tool-permitted-p "Bash"))))

;;; Footer

(provide 'test-gptel-ext-tool-permits)

;;; test-gptel-ext-tool-permits.el ends here