;;; gptel-tools-memory.el --- Agent-callable mementum memory tools -*- no-byte-compile: t; lexical-binding: t; -*-

;; Inspired by Serena's memory tools (read_memory, write_memory, list_memories,
;; delete_memory, edit_memory). Exposes our mementum system as gptel tools
;; so the AI agent can read and store insights during conversations.

(require 'cl-lib)
(require 'subr-x)

(defcustom gptel-tools-memory-dir "mementum/memories"
  "Directory for mementum memory files relative to project root."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-tools-memory-knowledge-dir "mementum/knowledge"
  "Directory for mementum knowledge pages relative to project root."
  :type 'directory
  :group 'gptel-tools-agent)

(defvar gptel-tools-memory--cached-root nil
  "Cached project root to avoid repeated lookups.")

(defun gptel-tools-memory--project-root ()
  "Return project root or default-directory.
Uses caching to avoid repeated filesystem lookups."
  (if (and gptel-tools-memory--cached-root
           (stringp gptel-tools-memory--cached-root))
      gptel-tools-memory--cached-root
    (setq gptel-tools-memory--cached-root
          (or (and (fboundp 'gptel-auto-workflow--project-root)
                   (gptel-auto-workflow--project-root))
              (and (fboundp 'project-root)
                   (project-root (project-current)))
              default-directory))))

(defun gptel-tools-memory--invalidate-cache ()
  "Invalidate cached project root. Call when project changes."
  (setq gptel-tools-memory--cached-root nil))

(defun gptel-tools-memory--resolve-path (slug &optional knowledge-p)
  "Resolve SLUG to an absolute file path.
If KNOWLEDGE-P, use knowledge directory; otherwise memories."
  (let* ((root (gptel-tools-memory--project-root))
         (base-dir (expand-file-name
                    (if knowledge-p
                        gptel-tools-memory-knowledge-dir
                      gptel-tools-memory-dir)
                    root))
         (filename (if (string-suffix-p ".md" slug) slug (concat slug ".md"))))
    (expand-file-name filename base-dir)))

(defun gptel-tools-memory--read (slug &optional knowledge-p)
  "Read a memory or knowledge file by SLUG.
Returns content string or error message."
  (let ((path (gptel-tools-memory--resolve-path slug knowledge-p)))
    (cond
     ((not (file-exists-p path))
      (format "Memory '%s' not found at %s" slug path))
     ((not (file-readable-p path))
      (format "Memory '%s' exists but is not readable" slug))
     (t
      (with-temp-buffer
        (insert-file-contents path)
        (buffer-string))))))

(defun gptel-tools-memory--write (slug content &optional knowledge-p)
  "Write CONTENT to a memory file identified by SLUG.
Returns success message or error."
  (let ((path (gptel-tools-memory--resolve-path slug knowledge-p)))
    (condition-case err
        (progn
          (make-directory (file-name-directory path) t)
          (with-temp-buffer
            (insert content)
            (write-region (point-min) (point-max) path nil 'silent))
          (format "Memory '%s' written (%d chars)" slug (length content)))
      (error (format "Error writing memory '%s': %s" slug (error-message-string err))))))

(defun gptel-tools-memory--list (&optional topic)
  "List available memories, optionally filtered by TOPIC."
  (let* ((root (gptel-tools-memory--project-root))
         (mem-dir (expand-file-name gptel-tools-memory-dir root))
         (know-dir (expand-file-name gptel-tools-memory-knowledge-dir root))
         (results (cl-loop for dir in (list mem-dir know-dir)
                          when (file-directory-p dir)
                          append (cl-loop for f in (directory-files-recursively dir "\\.md$")
                                         for rel = (file-relative-name f root)
                                         for name = (file-name-sans-extension (file-relative-name f dir))
                                         when (or (not topic)
                                                  (string-match-p (regexp-quote topic) name))
                                         collect (format "%s (%s)"
                                                        name
                                                        (if (string-prefix-p "mementum/knowledge" rel)
                                                            "knowledge" "memory"))))))
    (if results
        (format "Available memories (%d):\n%s"
                (length results)
                (string-join (sort results #'string<) "\n"))
      "No memories found.")))

(defun gptel-tools-memory-register ()
  "Register mementum memory tools with gptel."
  (when (fboundp 'gptel-make-tool)

    (gptel-make-tool
     :name "read_memory"
     :description "Read a mementum memory or knowledge file by name/slug. \
Use this to recall project-specific insights, patterns, or architecture notes \
that were stored in previous sessions. You can infer relevance from the memory name."
     :function #'gptel-tools-memory--read
     :args (list '(:name "slug"
                          :type string
                          :description "Memory name/slug (e.g., 'serena-architecture-lessons' or 'project-facts'). Add 'knowledge/' prefix for knowledge pages.")
                 '(:name "knowledge"
                          :type boolean
                          :optional t
                          :description "Set true to read from knowledge pages instead of memories."))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "write_memory"
     :description "Write information to a mementum memory file for future sessions. \
Use this when you discover a pattern, anti-pattern, or insight that would help \
a future AI session working on this project. Keep memories atomic (<200 words)."
     :function #'gptel-tools-memory--write
     :args (list '(:name "slug"
                        :type string
                        :description "Memory name/slug (e.g., 'nil-safety-pattern'). Use '/' for topics: 'auth/login-flow'.")
                 '(:name "content"
                        :type string
                        :description "The memory content in markdown format. Keep under 200 words. One insight per memory.")
                 '(:name "knowledge"
                        :type boolean
                        :optional t
                        :description "Set true to write to knowledge pages instead of memories."))
     :category "gptel-agent"
     :confirm t
     :include t)

    (gptel-make-tool
     :name "list_memories"
     :description "List available mementum memories and knowledge pages. \
Use this to discover what project knowledge has been captured from previous sessions."
     :function #'gptel-tools-memory--list
     :args (list '(:name "topic"
                          :type string
                          :optional t
                          :description "Filter memories by topic substring."))
     :category "gptel-agent"
     :include t)))

(provide 'gptel-tools-memory)
