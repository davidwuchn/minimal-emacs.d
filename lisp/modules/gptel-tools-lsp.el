;;; gptel-tools-lsp.el --- LSP tools for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; LSP integration tools for gptel-agent via Eglot and Flymake.

(require 'cl-lib)
(require 'jsonrpc)
(require 'eglot)
(require 'flymake)
(require 'project)
(require 'seq)

;;; Customization

(defgroup gptel-tools-lsp nil
  "LSP tool integrations for gptel-agent."
  :group 'gptel)

;;; Internal Helpers

(defun my/gptel-lsp--get-server (path)
  "Get the Eglot server for PATH, reliably."
  (let* ((proj (project-current nil path))
         (servers (and proj (hash-table-values eglot--servers-by-project)))
         (server (cl-find-if
                  (lambda (s)
                    (let ((s-proj (eglot--project s)))
                      (and s-proj
                           (equal (project-root s-proj)
                                  (project-root proj)))))
                  servers)))
    (or server (eglot-current-server))))

(defun my/gptel-lsp--path-to-uri (path)
  "Convert PATH to a file URI."
  (concat "file://" (expand-file-name path)))

(defun my/gptel-lsp--uri-to-path (uri)
  "Convert URI to a file path."
  (if (string-prefix-p "file://" uri)
      (substring uri 7)
    uri))

(defun my/gptel-lsp--format-location (loc)
  "Format an LSP Location or LocationLink object LOC into a readable string."
  (let* ((uri (or (plist-get loc :uri)
                  (plist-get loc :targetUri)))
         (range (or (plist-get loc :range)
                    (plist-get loc :targetSelectionRange)))
         (start (plist-get range :start))
         (line (plist-get start :line))
         (char (plist-get start :character))
         (path (my/gptel-lsp--uri-to-path uri)))
    (format "%s:%d:%d" path line char))) ; Keep 0-indexed for agent output

;;; Tool Implementations

(defun my/gptel-lsp-diagnostics (callback)
  "Get project-wide diagnostics from Flymake."
  (unless (fboundp 'flymake--project-diagnostics)
    (funcall callback "Error: flymake--project-diagnostics not available (requires Emacs 29+)")
    (cl-return-from my/gptel-lsp-diagnostics))
  
  (let* ((proj (project-current))
         (diags (and proj (flymake--project-diagnostics proj))))
    (if (not diags)
        (funcall callback "No diagnostics found for the current project.")
      (let ((formatted
             (mapcar (lambda (d)
                       (let ((buf (flymake-diagnostic-buffer d))
                             (text (flymake-diagnostic-text d))
                             (type (flymake-diagnostic-type d))
                             (beg (flymake-diagnostic-beg d)))
                         (with-current-buffer buf
                           (save-excursion
                             (goto-char beg)
                             (format "%s:%d:%d [%s] %s"
                                     (buffer-file-name buf)
                                     (1- (line-number-at-pos)) ; 0-indexed line
                                     (current-column)          ; 0-indexed char
                                     type text)))))
                     diags)))
        (funcall callback (string-join formatted "\n"))))))

(defun my/gptel-lsp-references (callback file-path line character)
  "Get LSP references for the symbol at FILE-PATH, LINE, CHARACTER (0-indexed)."
  (let ((server (my/gptel-lsp--get-server file-path)))
    (unless server
      (funcall callback (format "Error: No active Eglot server found for %s" file-path))
      (cl-return-from my/gptel-lsp-references))
    
    (jsonrpc-async-request
     server
     :textDocument/references
     (list :textDocument (list :uri (my/gptel-lsp--path-to-uri file-path))
           :position (list :line line :character character)
           :context (list :includeDeclaration t))
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No references found.")
                     (let ((formatted (mapcar #'my/gptel-lsp--format-location res)))
                       (funcall callback (string-join formatted "\n")))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback "LSP Request timed out.")))))

(defun my/gptel-lsp-workspace-symbol (callback query)
  "Query workspace symbols for QUERY."
  (let ((server (my/gptel-lsp--get-server default-directory)))
    (unless server
      (funcall callback "Error: No active Eglot server found for the current project")
      (cl-return-from my/gptel-lsp-workspace-symbol))
    
    (jsonrpc-async-request
     server
     :workspace/symbol
     (list :query query)
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No symbols found.")
                     (let ((formatted
                            (mapcar (lambda (sym)
                                      (let* ((name (plist-get sym :name))
                                             (kind (plist-get sym :kind))
                                             (loc (plist-get sym :location))
                                             (loc-str (my/gptel-lsp--format-location loc)))
                                        (format "[%s] %s -> %s" kind name loc-str)))
                                    res)))
                       (funcall callback (string-join formatted "\n")))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback "LSP Request timed out.")))))

;;; Tool Registration

(defun gptel-tools-lsp-register ()
  "Register LSP tools with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "lsp_diagnostics"
     :description "Get project-wide diagnostics/errors from the LSP server."
     :function #'my/gptel-lsp-diagnostics
     :args nil
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_references"
     :description "Find references for a symbol at a specific file, line, and character (0-indexed)."
     :function #'my/gptel-lsp-references
     :args '((:name "file_path" :type string)
             (:name "line" :type integer :description "0-indexed line number")
             (:name "character" :type integer :description "0-indexed character position"))
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_workspace_symbol"
     :description "Search for symbols across the entire workspace/project."
     :function #'my/gptel-lsp-workspace-symbol
     :args '((:name "query" :type string))
     :category "gptel-agent"
     :async t
     :include t)))

(provide 'gptel-tools-lsp)

;;; gptel-tools-lsp.el ends here