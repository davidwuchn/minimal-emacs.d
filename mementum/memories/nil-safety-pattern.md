# Nil-Safety Pattern for Elisp

When working with gptel-auto-workflow modules (highest failure rates):

```elisp
;; Validation guard pattern
(when (and target (stringp target) (not (string-empty-p target)))
  ...)

;; Or with optional with-nil-safe helper:
(defmacro with-nil-safe (&rest body)
  "Execute BODY, returning nil on any error."
  `(condition-case nil (progn ,@body) (error nil)))

;; Collection access pattern:
(when-let* ((coll (or some-collection nil))
            (item (alist-get key coll)))
  ...)
```

Apply these guards to functions in evolution.el, strategic.el, and ontology-router.el.
