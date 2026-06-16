;;; gptel-tools-memory.el --- Agent-callable mementum memory tools -*- no-byte-compile: t; lexical-binding: t; -*-

;; Inspired by Serena's memory tools (read_memory, write_memory, list_memories,
;; delete_memory, edit_memory). Exposes our mementum system as gptel tools
;; so the AI agent can read and store insights during conversations.

(defvar root nil)
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
Uses caching to avoid repeated filesystem lookups.
SIGNALS an error if no valid root can be determined."
  (if (and (stringp gptel-tools-memory--cached-root)
           (not (string= gptel-tools-memory--cached-root "")))
      gptel-tools-memory--cached-root
    (let ((_root (or (and (fboundp 'gptel-auto-workflow--project-root)
                         (funcall (symbol-function 'gptel-auto-workflow--project-root)))
                    (and (fboundp 'project-root)
                         (project-root (project-current)))
                    default-directory)))
      (unless (stringp _root)
        (error "gptel-tools-memory: Could not determine project root; all fallback methods
returned nil"))
      (when (string= _root "")
        (error "gptel-tools-memory: Project root resolved to empty string"))
      (setq gptel-tools-memory--cached-root _root)
      _root)))

(defun gptel-tools-memory--invalidate-cache ()
  "Invalidate cached project root. Call when project changes."
  (setq gptel-tools-memory--cached-root nil))

(defun gptel-tools-memory--resolve-path (slug &optional knowledge-p)
  "Resolve SLUG to an absolute file path.
If KNOWLEDGE-P, use knowledge directory; otherwise memories.
SIGNALS an error if SLUG contains path traversal or invalid characters."
  (when (null slug)
    (error "Slug must not be nil"))
  (when (string= slug "")
    (error "Slug must not be empty"))
  (when (and knowledge-p (not (booleanp knowledge-p)))
    (error "Knowledge-p must be a boolean, got: %S" knowledge-p))
  ;; ASSUMPTION: Slugs should be safe filenames across platforms
  ;; EDGE CASE: Reject null bytes, control chars, and Windows-invalid chars
  (when (string-match-p "[\x00-\x1f]" slug)
    (error "Slug must not contain control characters"))
  (when (string-match-p "[<>:\"|?*]" slug)
    (error "Slug must not contain characters invalid on Windows filesystems: <>:\"|?*"))
  (when (string-match-p "\\.\\./" slug)
    (error "Slug must not contain path traversal sequences"))
  (when (or (string-prefix-p "/" slug)
            (string-prefix-p "\\" slug))
    (error "Slug must not start with a path separator"))
  (let* ((_root (gptel-tools-memory--project-root))
         (_ (when (null _root)

              (error "Project root must not be nil; check `gptel-tools-memory--project-root'")))
         (base-dir (expand-file-name
                    (if knowledge-p
                        gptel-tools-memory-knowledge-dir
                      gptel-tools-memory-dir)
                    _root))
         (filename (if (string-suffix-p ".md" slug) slug (concat slug ".md")))
         (resolved (expand-file-name filename base-dir)))
    ;; DEFENSE: Verify resolved path is contained within base-dir
    ;; EDGE CASE: Prevents traversal via symlinks or platform-specific separators
    (unless (string-prefix-p (file-name-as-directory base-dir) resolved)
      (error "Resolved path escapes base directory: %s" resolved))
    resolved))

(defun gptel-tools-memory--read (slug &optional knowledge-p)
  "Read a memory or knowledge file by SLUG.
Returns content string or error message."
  (when (null slug)
    (error "Slug must not be nil"))
  (let ((path (gptel-tools-memory--resolve-path slug knowledge-p)))
    (cond
     ((not (file-exists-p path))
      (format "Memory '%s' not found at %s" slug path))
     ((not (file-regular-p path))
      (format "Memory '%s' is not a regular file" slug))
     ((not (file-readable-p path))
      (format "Memory '%s' exists but is not readable" slug))
     (t
      (with-temp-buffer
        (insert-file-contents path)
        (let ((content (buffer-string)))
          (if (string-blank-p content)
              (format "Memory '%s' is empty" slug)
            content)))))))

(defcustom gptel-tools-memory-max-content-size 1048576
  "Maximum content size in bytes (default 1MB) to prevent memory exhaustion."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-tools-memory--write (slug content &optional knowledge-p)
  "Write CONTENT to a memory file identified by SLUG.
Returns success message or error."
  (when (null slug)
    (error "Slug must not be nil"))
  (when (null content)
    (error "Content must not be nil"))
  (unless (stringp content)
    (error "Content must be a string, got: %S" content))
  (when (string-blank-p content)
    (error "Content must not be empty or whitespace-only"))
  (when (> (length content) gptel-tools-memory-max-content-size)
    (error "Content exceeds maximum size of %d bytes (got %d)"
           gptel-tools-memory-max-content-size (length content)))
  (let ((path (gptel-tools-memory--resolve-path slug knowledge-p)))
    (condition-case err
        (progn
          (make-directory (file-name-directory path) t)
          (with-temp-buffer
            (insert content)
            (write-region (point-min) (point-max) path nil 'silent))
          (format "Memory '%s' written (%d chars)" slug (length content)))
      (error (format "Error writing memory '%s': %s" slug (error-message-string err))))))

(defun gptel-tools-memory--collect-dir (dir type-label root &optional topic)
  "Collect memory entries from DIR with TYPE-LABEL.
Each entry is formatted as \"name (type-label)\".
If TOPIC is a non-empty string, filter by topic match.
SIGNALS an error if TOPIC is a non-string, non-nil value."
  (when (and topic
             (not (stringp topic)))
    (error "Topic must be a string, nil, or empty string, got: %S" topic))
  (when (null type-label)
    (error "Type-label must not be nil"))
  (when (and (stringp dir) (file-directory-p dir))
    (cl-loop for f in (directory-files-recursively dir "\\.md$")
             for base = (file-name-sans-extension (file-name-nondirectory f))
             when (or (null topic)
                      (string= topic "")
                      (string-match-p (regexp-quote topic) base))
             collect (format "%s (%s)" base type-label))))

(defun gptel-tools-memory--list (&optional topic)
  "List available memories, optionally filtered by TOPIC."
  (let* ((_root (gptel-tools-memory--project-root))
         (_ (when (null _root)

              (error "Project root must not be nil; check `gptel-tools-memory--project-root'")))
         (mem-dir (expand-file-name gptel-tools-memory-dir _root))
         (know-dir (expand-file-name gptel-tools-memory-knowledge-dir _root))
         (results (append (gptel-tools-memory--collect-dir mem-dir "memory" root topic)
                          (gptel-tools-memory--collect-dir know-dir "knowledge" root topic))))
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
                          :description "Memory name/slug (e.g., 'serena-architecture-lessons' or 'project-facts'). Add
'knowledge/' prefix for knowledge pages.")
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
                        :description "Memory name/slug (e.g., 'nil-safety-pattern'). Use '/' for topics:
'auth/login-flow'.")
                 '(:name "content"
                        :type string
                        :description "The memory content in markdown format. Keep under 200 words. One insight per
memory.")
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
