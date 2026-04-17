;;; test-gptel-gemini.el --- Tests for Gemini backend tool schemas -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-gemini)

(defun test-gptel-gemini--schema-contains-key-p (value key)
  "Return non-nil when VALUE recursively contains plist KEY."
  (cond
   ((vectorp value)
    (cl-loop for element across value
             thereis (test-gptel-gemini--schema-contains-key-p element key)))
   ((and (listp value) (keywordp (car value)))
    (or (plist-member value key)
        (cl-loop for (_ nested) on value by #'cddr
                 thereis (test-gptel-gemini--schema-contains-key-p nested key))))
   ((listp value)
    (cl-loop for element in value
             thereis (test-gptel-gemini--schema-contains-key-p element key)))
   (t nil)))

(ert-deftest gptel-gemini/filter-schema-strips-nested-optional-markers ()
  "Gemini schema filtering should strip nested `:optional' markers."
  (let* ((schema
          (list :type "object"
                :properties
                (list :entries
                      (list :type "array"
                            :items
                            (list :type "object"
                                  :properties
                                  (list :kind (list :type "string")
                                        :value
                                        (list :type "object"
                                              :properties
                                              (list :requiredField (list :type "string")
                                                    :activeForm (list :type "string" :optional t)
                                                    :node (list :type "string" :optional t))))
                                  :optional t)))))
         (filtered (gptel--gemini-filter-schema (copy-tree schema))))
    (should-not (test-gptel-gemini--schema-contains-key-p filtered :optional))
    (should (equal (plist-get filtered :type) "object"))))

(provide 'test-gptel-gemini)
;;; test-gptel-gemini.el ends here
