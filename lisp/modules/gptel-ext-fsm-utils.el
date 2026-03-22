;;; gptel-ext-fsm-utils.el --- Shared FSM helpers -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'gptel)

(defun my/gptel--fsm-p (object)
  "Return non-nil when OBJECT behaves like a `gptel-fsm'."
  (ignore-errors
    (gptel-fsm-state object)
    t))

(defun my/gptel--coerce-fsm (object)
  "Return the first `gptel-fsm' found inside OBJECT.

OBJECT may already be an FSM struct, a request-alist entry of the form
`(PROCESS FSM . CLEANUP)', a cons cell like `(FSM . CLEANUP)', or an
accidentally wrapped list like `(FSM)'.

TODO: This returns the first FSM found, which may be incorrect in
nested subagent scenarios where parent and child FSMs coexist.
A proper fix would require FSM ID tracking or parent pointers.
For now, callers should validate the returned FSM matches expected context."
  (cond
   ((my/gptel--fsm-p object) object)
   ((consp object)
    (or (my/gptel--coerce-fsm (car object))
        (my/gptel--coerce-fsm (cdr object))))
   (t nil)))

(provide 'gptel-ext-fsm-utils)

;;; gptel-ext-fsm-utils.el ends here
