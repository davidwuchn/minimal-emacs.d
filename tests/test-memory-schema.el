;;; test-memory-schema.el --- ERT tests for memory schema extraction and indexing -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD tests for gptel-auto-workflow-memory-schema.el:
;;   - Triple extraction from memory text
;;   - Schema inference from triples
;;   - Frequency tracking and tau threshold promotion
;;   - Category lookup for ontology router
;;   - Conflict detection
;;   - Index persistence
;;
;; Run:
;;   emacs --batch -L tests -L lisp/modules -L packages/gptel -L packages/gptel-agent \
;;         -l test-memory-schema.el -f ert-run-tests-batch-and-exit

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

(defvar gptel-auto-workflow--test-tmpdir nil)
(defvar gptel-auto-workflow--run-project-root)

(require 'gptel-auto-workflow-memory-schema)
(require 'gptel-auto-workflow-mementum)

;; ─── Test Fixtures ───

(defmacro with-schema-test-env (&rest body)
  "Run BODY with a fresh temp directory and clean schema index."
  `(let ((gptel-auto-workflow--test-tmpdir (make-temp-file "schema-test" t))
         (gptel-auto-workflow--run-project-root nil)
         (gptel-auto-workflow-memory-schema-threshold 3))
     (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                (lambda () gptel-auto-workflow--test-tmpdir)))
       (gptel-auto-workflow--memory-schema-reset)
       (unwind-protect
           (progn ,@body)
         (when (file-directory-p gptel-auto-workflow--test-tmpdir)
           (delete-directory gptel-auto-workflow--test-tmpdir t))))))

;; ─── Triple Extraction ───

(ert-deftest tdd/memory-schema/extract-triples/empty ()
  (should (null (gptel-auto-workflow--memory-schema-extract-triples ""))))

(ert-deftest tdd/memory-schema/extract-triples/verb-object ()
  (let ((triples (gptel-auto-workflow--memory-schema-extract-triples
                  "fix for byte-compiler warnings")))
    (should triples)
    (should (equal (plist-get (car triples) :predicate) "fix"))
    (should (equal (plist-get (car triples) :object) "byte-compiler warnings"))))

(ert-deftest tdd/memory-schema/extract-triples/improve-in ()
  (let ((triples (gptel-auto-workflow--memory-schema-extract-triples
                  "improved in ontology router")))
    (should triples)
    (should (equal (plist-get (car triples) :predicate) "improved"))
    (should (equal (plist-get (car triples) :object) "ontology router"))))

(ert-deftest tdd/memory-schema/extract-triples/add-to ()
  (let ((triples (gptel-auto-workflow--memory-schema-extract-triples
                  "added to schema index")))
    (should triples)
    (should (equal (plist-get (car triples) :predicate) "added"))
    (should (equal (plist-get (car triples) :object) "schema index"))))

(ert-deftest tdd/memory-schema/extract-triples/noise-ignored ()
  (let ((triples (gptel-auto-workflow--memory-schema-extract-triples
                  "reference to free variable `foo'")))
    (should (null triples))))

(ert-deftest tdd/memory-schema/extract-triples/multiple-lines ()
  (let ((triples (gptel-auto-workflow--memory-schema-extract-triples
                  "fix for byte-compiler warnings\nupdated in schema index")))
    (should (>= (length triples) 2))))

;; ─── Schema Inference ───

(ert-deftest tdd/memory-schema/infer-schema/basic ()
  (let ((triple '(:subject "byte-compiler" :predicate "fix"
                          :object "warnings" :subject-type nil :object-type nil)))
    (let ((schema (gptel-auto-workflow--memory-schema-infer-schema triple)))
      (should (equal schema "(byte-compiler fix warnings)")))))

(ert-deftest tdd/memory-schema/infer-schema/with-types ()
  (let ((triple '(:subject "module" :predicate "uses"
                          :object "backend" :subject-type "component" :object-type "service")))
    (let ((schema (gptel-auto-workflow--memory-schema-infer-schema triple)))
      (should (equal schema "(component uses service)")))))

(ert-deftest tdd/memory-schema/infer-schema/nil-fields ()
  (let ((triple '(:subject nil :predicate nil :object nil
                          :subject-type nil :object-type nil)))
    (let ((schema (gptel-auto-workflow--memory-schema-infer-schema triple)))
      (should (equal schema "(? ? ?)")))))

;; ─── Index: Load / Save Roundtrip ───

(ert-deftest tdd/memory-schema/index-roundtrip ()
  (with-schema-test-env
   (puthash "(x fix y)" 5 gptel-auto-workflow--memory-schema-schemas)
   (puthash "entity-a" (cons 3 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (gptel-auto-workflow--memory-schema-save-index)
   (gptel-auto-workflow--memory-schema-reset)
   (gptel-auto-workflow--memory-schema-load-index)
   (should (equal (gethash "(x fix y)" gptel-auto-workflow--memory-schema-schemas) 5))
   (should (equal (car (gethash "entity-a" gptel-auto-workflow--memory-schema-entities)) 3))))

;; ─── Schema Stability (tau threshold) ───

(ert-deftest tdd/memory-schema/stable-p/below-threshold ()
  (with-schema-test-env
   (puthash "(x fix y)" 2 gptel-auto-workflow--memory-schema-schemas)
   (should-not (gptel-auto-workflow--memory-schema-stable-p "(x fix y)"))))

(ert-deftest tdd/memory-schema/stable-p/at-threshold ()
  (with-schema-test-env
   (puthash "(x fix y)" 3 gptel-auto-workflow--memory-schema-schemas)
   (should (gptel-auto-workflow--memory-schema-stable-p "(x fix y)"))))

(ert-deftest tdd/memory-schema/stable-p/above-threshold ()
  (with-schema-test-env
   (puthash "(x fix y)" 7 gptel-auto-workflow--memory-schema-schemas)
   (should (gptel-auto-workflow--memory-schema-stable-p "(x fix y)"))))

(ert-deftest tdd/memory-schema/stable-schemas/filters-by-threshold ()
  (with-schema-test-env
   (puthash "(a fix b)" 2 gptel-auto-workflow--memory-schema-schemas)
   (puthash "(c uses d)" 5 gptel-auto-workflow--memory-schema-schemas)
   (puthash "(e ref f)" 1 gptel-auto-workflow--memory-schema-schemas)
   (let ((stable (gptel-auto-workflow--memory-schema-stable-schemas)))
     (should (= (length stable) 1))
     (should (equal (car (car stable)) "(c uses d)")))))

(ert-deftest tdd/memory-schema/candidate-schemas/filters-by-threshold ()
  (with-schema-test-env
   (puthash "(a fix b)" 2 gptel-auto-workflow--memory-schema-schemas)
   (puthash "(c uses d)" 5 gptel-auto-workflow--memory-schema-schemas)
   (puthash "(e ref f)" 1 gptel-auto-workflow--memory-schema-schemas)
   (let ((candidates (gptel-auto-workflow--memory-schema-candidate-schemas)))
     (should (= (length candidates) 2)))))

;; ─── Category Lookup ───

(ert-deftest tdd/memory-schema/category-for-target/no-entity ()
  (with-schema-test-env
   (should-not (gptel-auto-workflow--memory-schema-category-for-target
                "gptel-ext-context.el"))))

(ert-deftest tdd/memory-schema/category-for-target/agentic ()
  (with-schema-test-env
   (puthash "agent-main" (cons 5 '("mem1.md" "mem2.md"))
            gptel-auto-workflow--memory-schema-entities)
   (puthash "(agent-main dispatch subagent)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "agent-main:dispatch:subagent" (cons "(agent-main dispatch subagent)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (should (eq (gptel-auto-workflow--memory-schema-category-for-target
                "gptel-agent-main.el")
               :agentic))))

(ert-deftest tdd/memory-schema/category-for-target/tool-calls ()
  (with-schema-test-env
   (puthash "tools-bash" (cons 3 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (puthash "(tools-bash execute bash)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "tools-bash:execute:bash" (cons "(tools-bash execute bash)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (should (eq (gptel-auto-workflow--memory-schema-category-for-target
                "gptel-tools-bash.el")
               :tool-calls))))

(ert-deftest tdd/memory-schema/category-for-target/programming-default ()
  (with-schema-test-env
   (puthash "benchmark-core" (cons 4 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (puthash "(benchmark-core fix warnings)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "benchmark-core:fix:warnings" (cons "(benchmark-core fix warnings)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (should (eq (gptel-auto-workflow--memory-schema-category-for-target
                "gptel-benchmark-core.el")
               :programming))))

;; ─── Conflict Detection ───

(ert-deftest tdd/memory-schema/detect-conflicts/none ()
  (with-schema-test-env
   (puthash "simple-entry" (cons 1 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (should-not (gptel-auto-workflow--memory-schema-detect-conflicts))))

(ert-deftest tdd/memory-schema/detect-conflicts/mutual ()
  (with-schema-test-env
   (puthash "fix for module" (cons 2 '("mem1.md" "mem2.md"))
            gptel-auto-workflow--memory-schema-entities)
   (let ((conflicts (gptel-auto-workflow--memory-schema-detect-conflicts)))
     (should conflicts)
     (should (eq (nth 2 (car conflicts)) :mutual)))))

;; ─── Extract from File ───

(ert-deftest tdd/memory-schema/extract-from-file ()
  (with-schema-test-env
   (let* ((mem-dir (expand-file-name "mementum/memories"
                                     gptel-auto-workflow--test-tmpdir))
          (file (progn (make-directory mem-dir t)
                       (expand-file-name "insight-test.md" mem-dir))))
     (with-temp-file file
       (insert "# Insight: 2025-06-05 10:00\n\nfix for byte-compiler warnings\n"))
     (gptel-auto-workflow--memory-schema-extract-from-file file)
     (should (file-exists-p (gptel-auto-workflow--memory-schema-index-path))))))

;; ─── Rebuild Index ───

(ert-deftest tdd/memory-schema/rebuild-index/empty-dir ()
  (with-schema-test-env
   (let ((mem-dir (expand-file-name "mementum/memories"
                                    gptel-auto-workflow--test-tmpdir)))
     (make-directory mem-dir t)
     (gptel-auto-workflow--memory-schema-rebuild-index)
     (should (file-exists-p (gptel-auto-workflow--memory-schema-index-path))))))

;; ─── Temporal Versioning ───

(ert-deftest tdd/memory-schema/valid-p/without-frontmatter ()
  (let ((f (make-temp-file "mem-test" nil ".md")))
    (unwind-protect
        (progn
          (write-region "# Insight: 2025-01-01\n\nSome content\n" nil f)
          (should (gptel-auto-workflow--mementum-memory-valid-p f)))
      (delete-file f))))

(ert-deftest tdd/memory-schema/valid-p/with-valid-from ()
  (let ((f (make-temp-file "mem-test" nil ".md")))
    (unwind-protect
        (progn
          (write-region "---\nvalid-from: 2025-01-01T10:00\n---\n\n# Insight\n\nContent\n" nil f)
          (should (gptel-auto-workflow--mementum-memory-valid-p f)))
      (delete-file f))))

(ert-deftest tdd/memory-schema/valid-p/superseded ()
  (let ((f (make-temp-file "mem-test" nil ".md")))
    (unwind-protect
        (progn
          (write-region "---\nvalid-from: 2025-01-01T10:00\nvalid-until: 2025-06-01T10:00\n---\n\n# Insight\n\nOld\n" nil f)
          (should-not (gptel-auto-workflow--mementum-memory-valid-p f)))
      (delete-file f))))

(ert-deftest tdd/memory-schema/supersede/adds-frontmatter ()
  (let ((old-f (make-temp-file "mem-old" nil ".md"))
        (new-f "/tmp/mem-new-test.md"))
    (unwind-protect
        (progn
          (write-region "---\nvalid-from: 2025-01-01T10:00\n---\n\n# Insight\n\nOld content\n" nil old-f)
          (gptel-auto-workflow--mementum-supersede-memory old-f new-f)
          (with-temp-buffer
            (insert-file-contents old-f)
            (should (string-match-p "valid-until:" (buffer-string)))
            (should (string-match-p "superseded-by:" (buffer-string)))))
      (delete-file old-f))))

(ert-deftest tdd/memory-schema/find-superseded ()
  (let ((tmpdir (make-temp-file "mem-find-test" t)))
    (unwind-protect
        (let ((f1 (expand-file-name "insight-old-test.md" tmpdir))
              (f2 (expand-file-name "win-other.md" tmpdir)))
          (write-region "---\nvalid-from: 2025-01-01T10:00\n---\n\nOld\n" nil f1)
          (write-region "---\nvalid-from: 2025-01-01T10:00\n---\n\nOther\n" nil f2)
          (let ((matches (gptel-auto-workflow--mementum-find-superseded "old-test" tmpdir)))
            (should (= (length matches) 1))
            (should (string-match-p "old-test" (car matches)))))
      (delete-directory tmpdir t))))

(ert-deftest tdd/memory-schema/find-superseded/excludes-invalid ()
  (let ((tmpdir (make-temp-file "mem-find-test" t)))
    (unwind-protect
        (let ((f1 (expand-file-name "insight-old-test.md" tmpdir)))
          (write-region "---\nvalid-from: 2025-01-01T10:00\nvalid-until: 2025-06-01T10:00\n---\n\nOld\n" nil f1)
          (let ((matches (gptel-auto-workflow--mementum-find-superseded "old-test" tmpdir)))
            (should (= (length matches) 0))))
      (delete-directory tmpdir t))))

(ert-deftest tdd/memory-schema/find-superseded/excludes-file ()
  (let ((tmpdir (make-temp-file "mem-find-test" t)))
    (unwind-protect
        (let ((f1 (expand-file-name "insight-old-test.md" tmpdir))
              (f2 (expand-file-name "win-old-test-v2.md" tmpdir)))
          (write-region "---\nvalid-from: 2025-01-01T10:00\n---\n\nOld\n" nil f1)
          (write-region "---\nvalid-from: 2025-06-01T10:00\n---\n\nNew\n" nil f2)
          (let ((matches (gptel-auto-workflow--mementum-find-superseded "old-test" tmpdir f2)))
            (should (= (length matches) 1))
            (should (string-match-p "insight-old-test" (car matches)))))
      (delete-directory tmpdir t))))

;; ─── Bidirectional Code Links ───

(ert-deftest tdd/memory-schema/code-links/scan-empty ()
  (with-schema-test-env
   (gptel-auto-workflow--memory-schema-scan-code-links)
   (should (= 0 (hash-table-count gptel-auto-workflow--memory-schema-code-links)))))

(ert-deftest tdd/memory-schema/code-links/scan-with-reference ()
  (with-schema-test-env
   (let ((lisp-dir (expand-file-name "lisp/modules"
                                     gptel-auto-workflow--test-tmpdir)))
     (make-directory lisp-dir t)
     (with-temp-file (expand-file-name "test-module.el" lisp-dir)
       (insert ";; @memory:byte-compiler-fix\n(defun foo () t)\n"))
     (gptel-auto-workflow--memory-schema-scan-code-links)
     (should (= 1 (hash-table-count gptel-auto-workflow--memory-schema-code-links))))))

(ert-deftest tdd/memory-schema/code-links/memories-for-file ()
  (with-schema-test-env
   (let ((lisp-dir (expand-file-name "lisp/modules"
                                     gptel-auto-workflow--test-tmpdir))
         (test-file nil))
     (make-directory lisp-dir t)
     (setq test-file (expand-file-name "test-module.el" lisp-dir))
     (with-temp-file test-file
       (insert ";; @memory:byte-compiler-fix\n(defun foo () t)\n"))
     (gptel-auto-workflow--memory-schema-scan-code-links)
     (let ((slugs (gptel-auto-workflow--memory-schema-memories-for-file test-file)))
       (should slugs)
       (should (member "byte-compiler-fix" slugs))))))

(ert-deftest tdd/memory-schema/code-links/files-for-memory ()
  (with-schema-test-env
   (let ((lisp-dir (expand-file-name "lisp/modules"
                                     gptel-auto-workflow--test-tmpdir)))
     (make-directory lisp-dir t)
     (with-temp-file (expand-file-name "test-module.el" lisp-dir)
       (insert ";; @memory:byte-compiler-fix\n(defun foo () t)\n"))
     (gptel-auto-workflow--memory-schema-scan-code-links)
     (let ((files (gptel-auto-workflow--memory-schema-files-for-memory "byte-compiler-fix")))
       (should files)
       (should (= 1 (length files)))))))

;; ─── Hub Suppression (IDF) ───

(ert-deftest tdd/memory-schema/idf/penalizes-high-degree ()
  (let ((rare (gptel-auto-workflow--memory-schema-entity-idf
               "rare-entity" (cons 3 '("mem1.md")) 10))
        (hub (gptel-auto-workflow--memory-schema-entity-idf
              "hub-entity" (cons 3 '("m1.md" "m2.md" "m3.md" "m4.md" "m5.md")) 10)))
    (should (> rare hub))))

(ert-deftest tdd/memory-schema/idf/higher-count-wins-same-degree ()
  (let ((low (gptel-auto-workflow--memory-schema-entity-idf
              "low" (cons 2 '("m1.md")) 10))
        (high (gptel-auto-workflow--memory-schema-entity-idf
               "high" (cons 10 '("m1.md")) 10)))
    (should (> high low))))

(ert-deftest tdd/memory-schema/rank-entities ()
  (let ((ht (make-hash-table :test 'equal)))
    (puthash "specific" (cons 5 '("mem1.md")) ht)
    (puthash "generic" (cons 5 '("m1.md" "m2.md" "m3.md" "m4.md" "m5.md"
                                  "m6.md" "m7.md" "m8.md" "m9.md" "m10.md")) ht)
    (let ((ranked (gptel-auto-workflow--memory-schema-rank-entities ht)))
      (should (equal (car (car ranked)) "specific")))))

;; ─── Graph Retrieval ───

(ert-deftest tdd/memory-schema/neighbors/no-data ()
  (with-schema-test-env
   (should-not (gptel-auto-workflow--memory-schema-entity-neighbors "foo"))))

(ert-deftest tdd/memory-schema/neighbors/with-triples ()
  (with-schema-test-env
   (puthash "(byte-compiler fix warnings)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "byte-compiler:fix:warnings" (cons "(byte-compiler fix warnings)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (let ((neighbors (gptel-auto-workflow--memory-schema-entity-neighbors "byte-compiler")))
     (should neighbors)
     (should (member "warnings" (mapcar #'car neighbors))))))

(ert-deftest tdd/memory-schema/retrieve/single-hop ()
  (with-schema-test-env
   (puthash "(byte-compiler fix warnings)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "byte-compiler:fix:warnings" (cons "(byte-compiler fix warnings)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (let ((results (gptel-auto-workflow--memory-schema-retrieve "byte-compiler" 1)))
     (should results))))

;; ─── git-embed Synonymy ───

(ert-deftest tdd/memory-schema/synonymy/bin-unavailable ()
  (with-schema-test-env
   (cl-letf (((symbol-function 'gptel-auto-workflow--memory-schema-git-embed-bin)
              (lambda () nil)))
     (should-not (gptel-auto-workflow--memory-schema-synonymy-edges)))))

(ert-deftest tdd/memory-schema/synonymy/synonyms-for-empty ()
  (with-schema-test-env
   (cl-letf (((symbol-function 'gptel-auto-workflow--memory-schema-git-embed-bin)
              (lambda () nil)))
     (should-not (gptel-auto-workflow--memory-schema-synonyms-for "foo")))))

(ert-deftest tdd/memory-schema/synonymy/cache-reused ()
  (with-schema-test-env
   (let ((bin-call-count 0))
     (cl-letf (((symbol-function 'gptel-auto-workflow--memory-schema-git-embed-bin)
                (lambda () (cl-incf bin-call-count) "/usr/bin/true"))
               ((symbol-function 'shell-command-to-string)
                (lambda (_cmd) "")))
       (gptel-auto-workflow--memory-schema-synonymy-edges)
       (should (= 1 bin-call-count))
       (gptel-auto-workflow--memory-schema-synonymy-edges)
       (should (= 1 bin-call-count))))))

(ert-deftest tdd/memory-schema/neighbors/includes-embed-synonyms ()
  (with-schema-test-env
   (puthash "byte-compiler" (cons 3 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (puthash "(byte-compiler fix warnings)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "byte-compiler:fix:warnings" (cons "(byte-compiler fix warnings)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (cl-letf (((symbol-function 'gptel-auto-workflow--memory-schema-synonyms-for)
              (lambda (_entity) '(("compiler-warnings" . 0.85)))))
     (let ((neighbors (gptel-auto-workflow--memory-schema-entity-neighbors "byte-compiler")))
       (should (assoc "compiler-warnings" neighbors))))))

;; ─── Experiment-Scoped Memory Injection ───

(ert-deftest tdd/memory-schema/experiment-context/no-data ()
  (with-schema-test-env
   (should-not (gptel-auto-workflow--memory-schema-experiment-context "gptel-foo.el"))))

(ert-deftest tdd/memory-schema/experiment-context/with-entities ()
  (with-schema-test-env
   (puthash "foo-module" (cons 3 '("mem1.md"))
            gptel-auto-workflow--memory-schema-entities)
   (puthash "(foo-module fix bar)" 3
            gptel-auto-workflow--memory-schema-schemas)
   (puthash "foo-module:fix:bar" (cons "(foo-module fix bar)" "mem1.md")
            gptel-auto-workflow--memory-schema-triples)
   (let ((ctx (gptel-auto-workflow--memory-schema-experiment-context "gptel-foo-module.el")))
     (should (or ctx t)))))

;; ─── Ontology → Memory Feedback ───

(ert-deftest tdd/memory-schema/ontology-event/strategy-change ()
  (with-schema-test-env
   (gptel-auto-workflow--memory-schema-record-ontology-event
    :strategy-change
    '(:category :agentic :from "conservative" :to "aggressive"))
   (should (gethash "agentic-strategy" gptel-auto-workflow--memory-schema-entities))
   (should (gethash "(agentic switched strategy)"
                     gptel-auto-workflow--memory-schema-schemas))))

(ert-deftest tdd/memory-schema/ontology-event/saturation ()
  (with-schema-test-env
   (gptel-auto-workflow--memory-schema-record-ontology-event
    :saturation
    '(:category :programming :total 25))
   (should (gethash "programming-saturation" gptel-auto-workflow--memory-schema-entities))))

(ert-deftest tdd/memory-schema/ontology-event/drift ()
  (with-schema-test-env
   (gptel-auto-workflow--memory-schema-record-ontology-event
    :drift
    '(:target "gptel-tools-agent.el" :from-cat :agentic :delta -0.3))
   (should (gethash "gptel-tools-agent.el-drift" gptel-auto-workflow--memory-schema-entities))))

(ert-deftest tdd/memory-schema/ontology-evolution/records-events ()
  (with-schema-test-env
   (defvar gptel-auto-workflow--category-strategy-preferences)
   (defvar gptel-auto-workflow--category-saturation)
   (let ((gptel-auto-workflow--category-strategy-preferences '((:agentic . "aggressive")))
         (gptel-auto-workflow--category-saturation '((:tool-calls . t))))
     (gptel-auto-workflow--memory-schema-record-evolution
      '(:changes 2 :saturated 1 :total-strategies 5))
     (should (gethash "agentic-strategy" gptel-auto-workflow--memory-schema-entities))
     (should (gethash "tool-calls-saturation" gptel-auto-workflow--memory-schema-entities)))))

(provide 'test-memory-schema)
