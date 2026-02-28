;;; gptel-tools-ast.el --- AST tools for gptel-agent -*- lexical-binding: t -*-

(require 'gptel)
(require 'treesit-agent-tools)
(require 'treesit-agent-tools-workspace)

(defun gptel-tools-ast-register ()
  "Register the AST tools with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "AST_Map"
     :description "Get a high-level map of all functions and classes defined in a file. \
Useful for quickly understanding the structure of a Clojure/ClojureScript or Elisp file without reading it entirely."
     :function (lambda (file_path)
                 (condition-case err
                     (with-timeout (5 (format "Error: AST_Map timed out after 5 seconds on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         (let ((map (treesit-agent-get-file-map)))
                           (if map
                               (format "File map for %s:\n%s" file_path (string-join map "\n"))
                             (format "Could not generate file map for %s. Is tree-sitter enabled?" file_path)))))
                   (error (format "Error executing AST_Map on %s: %s" file_path (error-message-string err)))))
     :args (list '(:name "file_path" :type string :description "Path to the file to map"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "AST_Read"
     :description "Extract the exact, perfectly balanced code block for a specific function or class by name. \
MANDATORY tool for reading Clojure/ClojureScript or Elisp functions instead of Grep or Read."
     :function (lambda (file_path node_name)
                 (condition-case err
                     (with-timeout (5 (format "Error: AST_Read timed out after 5 seconds on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         (let ((text (treesit-agent-extract-node node_name)))
                           (if text
                               (format "AST Node '%s' from %s:\n\n%s" node_name file_path text)
                             (format "Error: Could not find AST node named '%s' in %s" node_name file_path)))))
                   (error (format "Error executing AST_Read on %s: %s" file_path (error-message-string err)))))
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to read"))
     :category "gptel-agent"
     :include t)

    (gptel-make-tool
     :name "AST_Replace"
     :description "Surgically replace an exact function or class by name with new code. \
MANDATORY tool for editing Clojure/ClojureScript or Elisp functions instead of standard Edit to ensure parentheses remain perfectly balanced."
     :function (lambda (file_path node_name new_code)
                 (condition-case err
                     (with-timeout (5 (format "Error: AST_Replace timed out after 5 seconds on %s" file_path))
                       (with-current-buffer (find-file-noselect file_path)
                         (if (treesit-agent-replace-node node_name new_code)
                             (progn
                               (save-buffer)
                               (format "Successfully replaced AST node '%s' in %s" node_name file_path))
                           (format "Error: Could not find AST node named '%s' to replace in %s" node_name file_path))))
                   (error (format "Error executing AST_Replace on %s: %s" file_path (error-message-string err)))))
     :args (list '(:name "file_path" :type string :description "Path to the file")
                 '(:name "node_name" :type string :description "Exact name of the function/class to replace")
                 '(:name "new_code" :type string :description "The perfectly balanced replacement code snippet"))
     :category "gptel-agent"
     :confirm t
     :include t)

    (gptel-make-tool
     :name "AST_Find_Workspace"
     :description "Search the entire project workspace for a function/class by name and extract its exact AST block. \
Use this when you don't know which file contains the definition."
     :function (lambda (node_name)
                 (condition-case err
                     (treesit-agent-find-workspace node_name)
                   (error (format "Error executing AST_Find_Workspace: %s" (error-message-string err)))))
     :args (list '(:name "node_name" :type string :description "Exact name of the function/class to find"))
     :category "gptel-agent"
     :include t)))

(provide 'gptel-tools-ast)
