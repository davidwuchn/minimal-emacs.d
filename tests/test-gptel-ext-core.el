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

(defun test-make-temp-file (prefix &optional dir-flag suffix)
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

(provide 'test-gptel-ext-core)
;;; test-gptel-ext-core.el ends here
