;;; gptel-ext-learning.el --- Learning integration for nucleus -*- lexical-binding: t; -*-

;; Bridge between LEARNING.md and continuous-learning instinct files.
;; Auto-evolves instinct evidence/timestamps on git commit via
;; `git-commit-finish-hook'.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;;; Customization

(defgroup gptel-ext-learning nil
  "Learning integration for nucleus."
  :group 'gptel)

(defcustom my/learning-instincts-dirs
  (list (expand-file-name "~/.config/opencode/skill/continuous-learning/instincts"))
  "Directories containing instinct files.
Each directory is searched recursively for .md files with YAML frontmatter."
  :type '(repeat directory)
  :group 'gptel-ext-learning)

;;; Internal Functions

(defun my/learning--parse-frontmatter (text)
  "Extract YAML frontmatter from TEXT as an alist of (key . value) pairs.
Returns nil if no frontmatter found."
  (when (string-match "\\`---\n\\(\\(?:.*\n\\)*?\\)---\n" text)
    (let ((front (match-string 1 text))
          (result nil))
      (dolist (line (split-string front "\n" t))
        (when (string-match "^\\([a-zA-Z_-]+\\):\\s-*\\(.*\\)$" line)
          (push (cons (match-string 1 line) (match-string 2 line)) result)))
      (nreverse result))))

(defun my/learning--update-instinct (path)
  "Update evidence count and last-accessed date in instinct file at PATH."
  (when (file-readable-p path)
    (let* ((text (with-temp-buffer
                   (insert-file-contents path)
                   (buffer-string)))
           (date (format-time-string "%Y-%m-%d")))
      (when (string-match "\\`---\n\\(\\(?:.*\n\\)*?\\)---\n" text)
        (let* ((front (match-string 1 text))
               (rest (substring text (match-end 0)))
               ;; Increment evidence count
               (front (if (string-match "^evidence:\\s-*\\([0-9]+\\)" front)
                          (let ((count (1+ (string-to-number (match-string 1 front)))))
                            (replace-regexp-in-string
                             "^evidence:.*$"
                             (format "evidence: %d" count)
                             front))
                        (concat front "evidence: 1\n")))
               ;; Update last-accessed date
               (front (if (string-match "^last-accessed:" front)
                          (replace-regexp-in-string
                           "^last-accessed:.*$"
                           (format "last-accessed: %s" date)
                           front)
                        (concat front (format "last-accessed: %s\n" date))))
               (updated (concat "---\n" front "---\n" rest)))
          (unless (string= updated text)
            (with-temp-file path
              (insert updated))
            (message "[learning] λ(evolve) %s — evidence+1, accessed %s"
                     (file-name-nondirectory path) date)))))))

(defun my/learning--collect-instinct-files ()
  "Return list of all instinct .md files from `my/learning-instincts-dirs'."
  (let ((files nil))
    (dolist (dir my/learning-instincts-dirs)
      (when (file-directory-p dir)
        (setq files (append files (directory-files-recursively dir "\\.md\\'")))))
    files))

(defun my/learning--extract-learning-slugs (learning-text)
  "Extract heading slugs from LEARNING-TEXT.
Returns list of strings like \"LEARNING.md#section-name\"."
  (let ((pos 0)
        (slugs nil))
    (while (string-match "^## \\(.+\\)$" learning-text pos)
      (let* ((heading (match-string 1 learning-text))
             ;; Convert heading to GitHub-style slug
             (slug (downcase (replace-regexp-in-string
                              "[^a-zA-Z0-9 -]" ""
                              (replace-regexp-in-string
                               "\\s-+" "-" heading)))))
        (push (format "LEARNING.md#%s" slug) slugs))
      (setq pos (match-end 0)))
    (nreverse slugs)))

(defun my/learning-auto-evolve-after-commit ()
  "Auto-evolve instincts after a git commit.

Two triggers:
1. If any instinct files were directly committed, update their evidence.
2. If LEARNING.md was updated, find instinct files with matching
   `learning-ref' frontmatter and evolve them."
  (let* ((repo (or (and (boundp 'git-commit-repository)
                        git-commit-repository)
                   default-directory))
         (default-directory repo)
         (paths (condition-case nil
                    (process-lines "git" "diff" "--name-only" "HEAD~1")
                  (error nil)))
         (learning-updated (seq-find
                            (lambda (p) (string-match-p "\\`LEARNING\\.md\\'" p))
                            paths)))
    ;; Trigger 1: instinct files committed directly (in-repo instincts)
    (dolist (rel paths)
      (when (string-match-p "instincts/.*\\.md\\'" rel)
        (let ((abs (expand-file-name rel repo)))
          (when (file-readable-p abs)
            (my/learning--update-instinct abs)))))

    ;; Trigger 2: LEARNING.md updated → evolve instincts with matching learning-ref
    (when learning-updated
      (let* ((learning-path (expand-file-name "LEARNING.md" repo))
             (learning-text (when (file-readable-p learning-path)
                              (with-temp-buffer
                                (insert-file-contents learning-path)
                                (buffer-string))))
             (slugs (when learning-text
                      (my/learning--extract-learning-slugs learning-text))))
        (when slugs
          (let ((instinct-files (my/learning--collect-instinct-files)))
            (dolist (file instinct-files)
              (when (file-readable-p file)
                (let* ((text (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string)))
                       (front (my/learning--parse-frontmatter text))
                       (ref (cdr (assoc "learning-ref" front))))
                  (when (and ref (member ref slugs))
                    (my/learning--update-instinct file)))))))))))

;;; Setup

(with-eval-after-load 'git-commit
  (add-hook 'git-commit-finish-hook #'my/learning-auto-evolve-after-commit))

(provide 'gptel-ext-learning)
;;; gptel-ext-learning.el ends here
