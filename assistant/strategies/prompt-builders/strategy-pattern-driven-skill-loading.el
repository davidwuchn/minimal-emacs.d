;;; strategy-pattern-driven-skill-loading.el --- Load skills based on detected code patterns -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically loading relevant skills based on detected patterns improves targeted advice quality.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-pattern-driven-skill-loading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with pattern-driven skill loading.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (detected-patterns (detect-code-patterns target))
         (matched-skills (resolve-pattern-skills detected-patterns))
         (skill-context (build-skill-context matched-skills)))
    (concat base-prompt "\n\n;; Pattern-Detected Skill Context\n" skill-context)))

(defun detect-code-patterns (target)
  "Detect code patterns in TARGET file.
Returns list of pattern keywords."
  (let* ((file-content (when (file-exists-p target)
                         (with-temp-buffer
                           (insert-file-contents target)
                           (buffer-string))))
         (patterns nil))
    (when file-content
      (when (string-match-p "\\bclass\\b\\|\\bdefmethod\\b\\|\\bsend\\b" file-content)
        (push "oop" patterns))
      (when (string-match-p "\\brecurse\\b\\|\\byloop\\b\\|\\breduce\\b" file-content)
        (push "functional" patterns))
      (when (string-match-p "\\bdefmacro\\b\\|\\beval-when\\b" file-content)
        (push "macros" patterns))
      (when (string-match-p "\\basync\\b\\|\\bpromise\\b\\|\\bcallback\\b" file-content)
        (push "async" patterns))
      (when (string-match-p "\\bdefstruct\\b\\|\\bplist-get\\b\\|\\bplist-put\\b" file-content)
        (push "data-structures" patterns))
      (when (string-match-p "\\bcondition-case\\b\\|\\bsignal\\b\\|\\bthrow\\b" file-content)
        (push "error-handling" patterns))
      (when (string-match-p "\\bthread-first\\b\\|\\bthread-last\\b\\|-->" file-content)
        (push "threading" patterns)))
    (or patterns '("general"))))

(defun resolve-pattern-skills (patterns)
  "Map PATTERNS to relevant skill names."
  (let ((skill-mapping '(("oop" . "emacs-oop-patterns")
                         ("functional" . "functional-elisp")
                         ("macros" . "elisp-macro-design")
                         ("async" . "async-programming")
                         ("data-structures" . "data-structures")
                         ("error-handling" . "error-handling-patterns")
                         ("threading" . "threading-macros")
                         ("general" . "general-elisp"))))
    (delq nil (mapcar (lambda (p)
                        (cdr (assoc p skill-mapping)))
                      patterns))))

(defun build-skill-context (skill-names)
  "Build context string by loading SKILL-NAMES."
  (if (null skill-names)
      "No specialized patterns detected."
    (let ((skill-contents nil))
      (dolist (skill skill-names)
        (let ((content (condition-case nil
                           (gptel-auto-workflow--load-skill-content skill)
                         (error ""))))
          (when (> (length content) 0)
            (push (format "[%s]\n%s" skill content) skill-contents))))
      (if skill-contents
          (concat "Relevant skill guidance:\n\n"
                  (mapconcat 'identity (nreverse skill-contents) "\n\n"))
        "No specialized skills loaded."))))

(defun strategy-pattern-driven-skill-loading-get-metadata ()
  "Return metadata for this strategy."
  (list :name "pattern-driven-skill-loading"
        :version "1.0"
        :hypothesis "Dynamically loading relevant skills based on detected patterns improves targeted advice quality"
        :axis "E"
        :components ["pattern-detection" "dynamic-skill-loading"]))

(provide 'strategy-pattern-driven-skill-loading)