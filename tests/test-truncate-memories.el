;;; test-truncate-memories.el --- Tests for gptel-mementum--truncate-memories -*- lexical-binding: t; -*-

;; Minimal test file — only loads the module containing truncate-memories

;; We load the research module directly to test the pure function
;; without the full agent dependency chain.

;; Load dependencies minimally
(require 'cl-lib)
(require 'subr-x)

;; Provide stubs that research.el may need at load time
(unless (featurep 'gptel)
  (provide 'gptel))
(unless (featurep 'yaml)
  (provide 'yaml))
(unless (featurep 'gptel-agent)
  (provide 'gptel-agent))

;; Now load the module under test
(load (expand-file-name "lisp/modules/gptel-tools-agent-research.el"
                        (or (getenv "EMACS_D_ROOT") default-directory)))

(ert-deftest truncate-memories/drops-overflow-tail ()
  "When total capped memories exceed max-bytes, drop oldest (tail) memories.
Regression: overflow loop tracked dropped bytes instead of kept bytes,
so nothing was ever dropped and the function returned an oversized list."
  ;; 10 memories × 6000 chars = 60,000 total.  max-bytes = 15,000.
  ;; per-memory-cap = max(1000, 15000/4) = 3750, so each gets capped to 3750.
  ;; After capping: 10 × 3750 = 37,500 > 15,000.  Must drop from the tail.
  (let* ((memories (make-list 10 (make-string 6000 ?A)))
         (max-bytes 15000)
         (truncated (gptel-mementum--truncate-memories memories max-bytes))
         (total (apply #'+ (mapcar #'length truncated))))
    (should (<= total max-bytes))
    ;; Should keep at least some memories (not drop everything)
    (should (> (length truncated) 0))))

(ert-deftest truncate-memories/keeps-all-when-under-limit ()
  "When capped total is under max-bytes, all memories are preserved."
  (let* ((memories '("aaa" "bbb" "ccc"))
         (truncated (gptel-mementum--truncate-memories memories 1000)))
    (should (= (length truncated) 3))
    (should (equal truncated '("aaa" "bbb" "ccc")))))

(ert-deftest truncate-memories/caps-individual-oversized-memory ()
  "A single memory larger than per-memory-cap gets truncated."
  (let* ((big (make-string 50000 ?x))
         (truncated (gptel-mementum--truncate-memories (list big) 100000)))
    (should (= (length truncated) 1))
    (should (< (length (car truncated)) 50000))
    (should (string-match-p "truncated" (car truncated)))))

(ert-deftest truncate-memories/empty-list ()
  "Empty input returns empty output."
  (should (equal (gptel-mementum--truncate-memories nil 1000) nil)))

(ert-deftest truncate-memories/exact-fit ()
  "When total exactly equals max-bytes, all memories are kept."
  (let* ((memories '("aaaaa" "bbbbb"))  ; 5+5 = 10
         (truncated (gptel-mementum--truncate-memories memories 10)))
    (should (= (length truncated) 2))
    (should (<= (apply #'+ (mapcar #'length truncated)) 10))))
