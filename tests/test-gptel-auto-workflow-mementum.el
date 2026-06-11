;;; test-gptel-auto-workflow-mementum.el --- Tests for mementum integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-mementum.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-mementum.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-mementum)
(require 'gptel-auto-workflow-evolution)

;;; Customization tests

(ert-deftest test-mementum/enabled-default ()
  "Mementum should be enabled by default."
  (should gptel-auto-workflow-mementum-enabled))

(ert-deftest test-mementum/dir-default ()
  "Mementum dir should default to mementum."
  (should (equal gptel-auto-workflow-mementum-dir "mementum")))

(ert-deftest test-mementum/memory-dir-default ()
  "Memory dir should default to mementum/memories."
  (should (equal gptel-auto-workflow-mementum-memory-dir "mementum/memories")))

(ert-deftest test-mementum/knowledge-dir-default ()
  "Knowledge dir should default to mementum/knowledge."
  (should (equal gptel-auto-workflow-mementum-knowledge-dir "mementum/knowledge")))

;;; Symbol map tests

(ert-deftest test-mementum/symbol-map-exists ()
  "Symbol map should be defined."
  (should (listp gptel-auto-workflow--mementum-symbol-map)))

(ert-deftest test-mementum/symbol-prefix-insight ()
  "Symbol prefix for insight should be insight."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix '💡) "insight")))

(ert-deftest test-mementum/symbol-prefix-mistake ()
  "Symbol prefix for mistake should be mistake."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix '❌) "mistake")))

(ert-deftest test-mementum/symbol-prefix-unknown ()
  "Symbol prefix for unknown should be memory."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix 'unknown) "memory")))

;;; Slug tests

(ert-deftest test-mementum/slug-lowercases ()
  "Slug should lowercase text."
  (should (string-match-p "^[a-z]" (gptel-auto-workflow--mementum-slug "UPPERCASE"))))

(ert-deftest test-mementum/slug-replaces-spaces ()
  "Slug should replace spaces with hyphens."
  (should (string-match-p "-" (gptel-auto-workflow--mementum-slug "two words"))))

;; ─── Research recording guard tests ───

(defmacro with-mocked-write-memory (&rest body)
  "Execute BODY with mementum-write-memory mocked to capture calls."
  (declare (indent 0))
  `(let* ((write-calls nil)
          (gptel-auto-workflow-mementum-enabled t))
     (cl-letf (((symbol-function 'gptel-auto-workflow--mementum-write-memory)
                (lambda (&rest args)
                  (push args write-calls)
                  "/tmp/mock-path.md")))
       (ignore-errors
         (progn ,@body))
       write-calls)))

(ert-deftest test-mementum/research-skips-none-strategy ()
  "Research with strategy 'none' should not create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "none" :findings "test" :targets '() :kept-count 0 :total-count 0)))))
    (should (null calls))))

(ert-deftest test-mementum/research-skips-nil-string-strategy ()
  "Research with strategy 'nil' (string) should not create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "nil" :findings "test" :targets '() :kept-count 0 :total-count 0)))))
    (should (null calls))))

(ert-deftest test-mementum/research-skips-unknown-strategy ()
  "Research with strategy 'unknown' should not create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "unknown" :findings "test" :targets '() :kept-count 0 :total-count 0)))))
    (should (null calls))))

(ert-deftest test-mementum/research-skips-empty-strategy ()
  "Research with empty string strategy should not create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "" :findings "test" :targets '() :kept-count 0 :total-count 0)))))
    (should (null calls))))

(ert-deftest test-mementum/research-records-valid-strategy ()
  "Research with a valid strategy should create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "research-bug-fix" :findings "Found a bug" :targets '("foo.el") :kept-count 2 :total-count 5 :hash "abc123"))))
         ;; calls is list of (symbol slug content) args passed to write-memory
         (slug (when calls (nth 1 (car calls)))))
    (should calls)
    (should (string-match-p "research-bug-fix" (or slug "")))))

(ert-deftest test-mementum/research-records-nil-strategy-as-default ()
  "Research with nil strategy should default to 'default' and create a memory file."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :findings "test" :targets '() :kept-count 0 :total-count 0))))
         (slug (when calls (nth 1 (car calls)))))
    (should calls)
    (should (string-match-p "research-default" (or slug "")))))

(ert-deftest test-mementum/research-skips-none-strategy-case-insensitive ()
  "Research with strategy 'None' (capitalized) should also be skipped."
  (let* ((calls (with-mocked-write-memory
                  (gptel-auto-workflow--mementum-record-research
                   (list :strategy "None" :findings "test" :targets '() :kept-count 0 :total-count 0)))))
    (should (null calls))))

(provide 'test-gptel-auto-workflow-mementum)
;;; test-gptel-auto-workflow-mementum.el ends here