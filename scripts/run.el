(setq user-emacs-directory default-directory)
(load (expand-file-name "early-init.el" user-emacs-directory))
(load (expand-file-name "init.el" user-emacs-directory))
(message "CURRENT DIRECTIVES: %S" (mapcar 'car gptel-directives))
