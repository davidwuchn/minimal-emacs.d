;;; test-nucleus-prompts.el --- Tests for prompt loading -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for nucleus-prompts.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-nucleus-prompts.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nucleus-prompts)

;;; Customization tests

(ert-deftest test-prompts/prompts-dir-default ()
  "Prompts directory should be assistant/prompts."
  (should (string-match-p "assistant/prompts" nucleus-prompts-dir)))

(ert-deftest test-prompts/agents-dir-default ()
  "Agents directory should be assistant/agents."
  (should (string-match-p "assistant/agents" nucleus-agents-dir)))

(ert-deftest test-prompts/tool-prompts-dir-default ()
  "Tool prompts directory should be assistant/prompts/tools."
  (should (string-match-p "assistant/prompts/tools" nucleus-tool-prompts-dir)))

;;; Directory resolution tests

(ert-deftest test-prompts/resolve-prompts-dir ()
  "Resolve prompts dir should return nucleus-prompts-dir."
  (should (equal (nucleus--resolve-prompts-dir) nucleus-prompts-dir)))

(ert-deftest test-prompts/resolve-agents-dir ()
  "Resolve agents dir should return nucleus-agents-dir."
  (should (equal (nucleus--resolve-agents-dir) nucleus-agents-dir)))

(ert-deftest test-prompts/resolve-tool-prompts-dir ()
  "Resolve tool prompts dir should return nucleus-tool-prompts-dir."
  (should (equal (nucleus--resolve-tool-prompts-dir) nucleus-tool-prompts-dir)))

;;; File reading tests

(ert-deftest test-prompts/read-file-if-exists-missing ()
  "Read file if exists should return nil for missing file."
  (should-not (nucleus--read-file-if-exists "/nonexistent/file.md")))

(provide 'test-nucleus-prompts)
;;; test-nucleus-prompts.el ends here