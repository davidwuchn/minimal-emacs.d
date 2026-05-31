;;; gptel-auto-experiment-ai-behaviors.el --- ai-behaviors hashtag resolver for OV5

;; Resolves #hashtags from the ai-behaviors submodule at
;; packages/ai-behaviors/behaviors/<name>/{compose,prompt.md}.
;; Maps ontology categories to hashtag combinations and injects
;; the resolved content into executor prompts.

(defconst gptel-ai-behaviors-root
  (expand-file-name "packages/ai-behaviors/behaviors"
                    (or (bound-and-true-p minimal-emacs-user-directory)
                        user-emacs-directory))
  "Path to the ai-behaviors behaviors directory.")

(defvar gptel-ai-behaviors--expand-cache (make-hash-table :test 'equal)
  "Cache of hashtag → resolved content. Cleared on repo update.")

(defun gptel-ai-behaviors--repo-available-p ()
  "Return non-nil when the ai-behaviors submodule is present."
  (file-directory-p gptel-ai-behaviors-root))

(defun gptel-ai-behaviors--resolve-dir (name)
  "Resolve behavior directory for NAME, checking all overrides.
Resolution order: project-local (.ai-behaviors/) → user-local
(~/.config/ai-behaviors/) → repo (packages/ai-behaviors/behaviors/).
Returns directory path or nil."
  (or (let* ((proj-root (and (bound-and-true-p gptel-auto-workflow--current-project)
                             (expand-file-name gptel-auto-workflow--current-project)))
             (local-dir (and proj-root (expand-file-name (concat ".ai-behaviors/" name) proj-root))))
        (when (and local-dir (file-directory-p local-dir))
          local-dir))
      (let ((user-dir (expand-file-name (concat "~/.config/ai-behaviors/behaviors/" name))))
        (when (file-directory-p user-dir)
          user-dir))
      (let ((repo-dir (expand-file-name name gptel-ai-behaviors-root)))
        (when (file-directory-p repo-dir)
          repo-dir))))

(defun gptel-ai-behaviors--expand (hashtags &optional depth seen)
  "Expand HASHTAGS (space-separated, with # prefix) to leaf behaviors.
Resolves composites recursively (max depth 8). Returns (CONTENT . MODE-TAGS)
where CONTENT is the concatenated prompt.md text and MODE-TAGS is the
active operating mode tag (or nil)."
  (let ((content "")
        (mode-tag nil)
        (current-depth (or depth 0))
        (current-seen (or seen "")))
    (dolist (tag (split-string hashtags))
      (let ((name (substring tag 1)))  ; strip #
        (when-let ((dir (gptel-ai-behaviors--resolve-dir name)))
          (cond
           ;; Composite: has compose file — expand recursively
           ((file-exists-p (expand-file-name "compose" dir))
            (when (not (string-match-p (regexp-quote name) current-seen))
              (when (< current-depth 8)
                (let ((composed (with-temp-buffer
                                  (insert-file-contents (expand-file-name "compose" dir))
                                  (string-trim (buffer-string)))))
                  (when-let ((result (gptel-ai-behaviors--expand
                                      composed (1+ current-depth)
                                      (concat current-seen " " name))))
                    (setq content (concat content (car result)))
                    (when (and (cdr result) (not mode-tag))
                      (setq mode-tag (cdr result))))))))
           ;; Leaf behavior: has prompt.md — read content
           ((file-exists-p (expand-file-name "prompt.md" dir))
            (let ((md-content (with-temp-buffer
                                (insert-file-contents (expand-file-name "prompt.md" dir))
                                (string-trim (buffer-string)))))
              (setq content (concat content "\n" md-content "\n"))
              (when (string-prefix-p "#=" tag)
                (setq mode-tag tag))))))))
    (cons (string-trim content) mode-tag)))

(defun gptel-ai-behaviors--category-hashtags (category)
  "Return the hashtag string for CATEGORY (ai-behaviors format)."
  (pcase category
    (:agentic "#=code #contract #checklist #scope #legible #concise")
    (:programming "#=code #subtract #concrete #legible")
    (:tool-calls "#=code #defensive #boundary #robust #legible")
    (:natural-language "#=code #coherence #depth #concrete #legible")
    (_ "#=code #legible #concise")))

(defun gptel-ai-behaviors--inject (category)
  "Resolve hashtags for CATEGORY and return formatted context.
Returns empty string if ai-behaviors repo is not available."
  (when (and category (gptel-ai-behaviors--repo-available-p))
    (let* ((hashtags (gptel-ai-behaviors--category-hashtags category))
           (resolved (gptel-ai-behaviors--expand hashtags))
           (content (car resolved))
           (mode-tag (cdr resolved)))
      (when (> (length content) 0)
        (concat (if mode-tag
                    (format "<operating-mode name=\"%s\">\n%s\n</operating-mode>\n"
                            mode-tag content)
                  (format "<behavior-modifiers>\n%s\n</behavior-modifiers>\n"
                          content))
                "<framework>
HARD CONSTRAINTs define what the current mode IS — they are not overridable.
When a behavior modifier causes you to make a point you would not otherwise make,
mark it: (#name) after the sentence.
</framework>\n")))))

(defun gptel-ai-behaviors--inject-for-target (target)
  "Resolve ai-behaviors for TARGET's ontology category."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (gptel-ai-behaviors--inject
     (gptel-auto-workflow--categorize-target target))))

(provide 'gptel-auto-experiment-ai-behaviors)
;;; gptel-auto-experiment-ai-behaviors.el ends here
