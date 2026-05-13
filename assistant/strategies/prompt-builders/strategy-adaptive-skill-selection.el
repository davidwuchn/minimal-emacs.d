;;; strategy-adaptive-skill-selection.el --- Conditionally load skills based on file characteristics -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills tailored to file characteristics (mode, size, complexity) improves modification quality
;; Axis: E (Skill loading)
;;
;; This strategy analyzes the target file's characteristics and conditionally
;; loads relevant skills, rather than loading all skills uniformly.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-skill-selection-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using adaptive skill selection.
Skills are loaded based on file characteristics rather than uniformly."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (file-characteristics (strategy-ass--analyze-file target))
         (selected-skills (strategy-ass--select-relevant-skills file-characteristics))
         (skill-content (strategy-ass--load-skill-content selected-skills)))
    (if (string-empty-p skill-content)
        base-prompt
      (concat base-prompt "\n\n;; Adaptively Selected Skills\n" skill-content))))

(defun strategy-ass--analyze-file (target)
  "Analyze TARGET file and return characteristics plist."
  (let* ((file-size (nth 7 (file-attributes target))) ; size in bytes
         (line-count (strategy-ass--count-lines target))
         (major-mode (strategy-ass--detect-major-mode target))
         (complexity (strategy-ass--estimate-complexity target))
         (has-tests (strategy-ass--has-test-file target)))
    (list :size file-size
          :lines line-count
          :major-mode major-mode
          :complexity complexity
          :has-tests has-tests)))

(defun strategy-ass--count-lines (file-path)
  "Count lines in FILE-PATH."
  (let ((content (condition-case nil
                     (with-temp-buffer
                       (insert-file-contents file-path)
                       (buffer-string))
                   (error ""))))
    (length (split-string content "\n"))))

(defun strategy-ass--detect-major-mode (target)
  "Detect major mode based on TARGET file name and content."
  (let ((name (file-name-nondirectory target)))
    (cond
     ((string-match-p "\\-test\\.el$" name) 'ert)
     ((string-match-p "\\-tests\\.el$" name) 'ert)
     ((string-match-p "\\.el$" name) 'emacs-lisp)
     ((string-match-p "\\.org$" name) 'org)
     ((string-match-p "\\.py$" name) 'python)
     ((string-match-p "\\.js$" name) 'javascript)
     (t 'fundamental))))

(defun strategy-ass--estimate-complexity (target)
  "Estimate code complexity based on nesting depth and special forms."
  (let ((content (condition-case nil
                     (with-temp-buffer
                       (insert-file-contents target)
                       (buffer-string))
                   (error "")))
        (depth 0)
        (max-depth 0)
        (special-forms '("defun" "defmacro" "lambda" "let" "let*" "cond" "when" "if" "cl-loop" "dolist" "dotimes")))
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
          (when (string-match-p "(" line)
            (setq depth (1+ depth))
            (setq max-depth (max max-depth depth)))
          (when (string-match-p ")" line)
            (setq depth (max 0 (1- depth)))))
        (forward-line 1)))
    (cond
     ((>= max-depth 8) 'high)
     ((>= max-depth 5) 'medium)
     (t 'low))))

(defun strategy-ass--has-test-file (target)
  "Check if TARGET has a corresponding test file."
  (let ((base-name (file-name-sans-extension target)))
    (or (file-exists-p (concat base-name "-test.el"))
        (file-exists-p (concat base-name ".test.el"))
        (file-exists-p (concat base-name "_test.el")))))

(defun strategy-ass--select-relevant-skills (characteristics)
  "Select skills based on CHARACTERISTICS."
  (let ((selected '())
        (mode (plist-get characteristics :major-mode))
        (complexity (plist-get characteristics :complexity))
        (has-tests (plist-get characteristics :has-tests)))
    ;; Core skills always included
    (push "code-improvement" selected)
    (push "readability" selected)
    ;; Mode-specific skills
    (when (eq mode 'emacs-lisp)
      (push "elisp-patterns" selected)
      (push "emacs-conventions" selected))
    (when (eq mode 'ert)
      (push "ert-testing" selected))
    (when (eq mode 'org)
      (push "org-mode" selected))
    ;; Complexity-based skills
    (when (eq complexity 'high)
      (push "complexity-reduction" selected)
      (push "refactoring" selected))
    ;; Test-related skills
    (when has-tests
      (push "test-considerations" selected))
    (nreverse selected)))

(defun strategy-ass--load-skill-content (skill-names)
  "Load content for SKILL-NAMES."
  (let ((content ""))
    (dolist (skill-name skill-names)
      (let ((skill-content (condition-case nil
                               (gptel-auto-workflow--load-skill-content skill-name)
                             (error ""))))
        (unless (string-empty-p skill-content)
          (setq content (concat content "\n\n;; Skill: " skill-name "\n" skill-content)))))
    content))

(defun strategy-adaptive-skill-selection-get-metadata ()
  "Return metadata for this strategy."
  (list :name "adaptive-skill-selection"
        :version "1.0"
        :hypothesis "Conditionally loading skills based on file characteristics (mode, complexity, tests) provides more targeted guidance than uniform skill loading"
        :axis "E"
        :components ["file-analysis" "adaptive-selection" "skill-filtering"]))

(provide 'strategy-adaptive-skill-selection)