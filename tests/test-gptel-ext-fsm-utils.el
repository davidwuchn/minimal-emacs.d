;;; test-gptel-ext-fsm-utils.el --- FSM utils tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-fsm-utils)

(defun test-fsm-reset ()
  (clrhash my/gptel--fsm-registry)
  (setq my/gptel--fsm-id-counter 0)
  (setq my/gptel--fsm-predicate-fn nil))

(defun test-fsm-make ()
  (gptel-make-fsm :state 'WAIT :table gptel-request--transitions
                  :handlers gptel-request--handlers :info nil))

;; Predicate tests

(ert-deftest test-fsm/predicate-resolve-is-function ()
  (should (functionp (my/gptel--fsm-predicate-resolve))))

(ert-deftest test-fsm/predicate-is-gptel-fsm-p ()
  (setq my/gptel--fsm-predicate-fn nil)
  (should (eq (my/gptel--fsm-predicate-resolve) #'gptel-fsm-p)))

(ert-deftest test-fsm/fsm-p-valid ()
  (should (my/gptel--fsm-p (test-fsm-make))))

(ert-deftest test-fsm/fsm-p-nil ()
  (should-not (my/gptel--fsm-p nil)))

(ert-deftest test-fsm/fsm-p-string ()
  (should-not (my/gptel--fsm-p "x")))

(ert-deftest test-fsm/fsm-valid-p-nil ()
  (should-not (my/gptel--fsm-valid-p nil)))

;; ID generation tests

(ert-deftest test-fsm/gen-id-string ()
  (test-fsm-reset)
  (should (stringp (my/gptel--fsm-generate-id))))

(ert-deftest test-fsm/gen-id-format ()
  (test-fsm-reset)
  (should (string-match-p "^fsm-[0-9]+-[0-9]+\\.[0-9]+$"
                           (my/gptel--fsm-generate-id))))

(ert-deftest test-fsm/gen-id-unique ()
  (test-fsm-reset)
  (let ((a (my/gptel--fsm-generate-id)))
    (should-not (equal a (my/gptel--fsm-generate-id)))))

;; Registration tests

(ert-deftest test-fsm/register-id ()
  (test-fsm-reset)
  (let ((id (my/gptel--fsm-register (test-fsm-make))))
    (should (stringp id))))

(ert-deftest test-fsm/register-nil ()
  (test-fsm-reset)
  (should-not (my/gptel--fsm-register nil)))

(ert-deftest test-fsm/register-idempotent ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (should (equal (my/gptel--fsm-register fsm)
                   (my/gptel--fsm-register fsm)))))

;; Unregister tests  

(ert-deftest test-fsm/unregister-by-fsm ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (my/gptel--fsm-register fsm)
    (my/gptel--fsm-unregister fsm)
    (should-not (gethash fsm my/gptel--fsm-registry))))

(ert-deftest test-fsm/unregister-by-id ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (let ((id (my/gptel--fsm-register fsm)))
      (my/gptel--fsm-unregister id)
      (should-not (gethash fsm my/gptel--fsm-registry)))))

(ert-deftest test-fsm/unregister-unknown ()
  (should-not (my/gptel--fsm-unregister "x")))

;; Lookup tests

(ert-deftest test-fsm/get-by-id ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (let ((id (my/gptel--fsm-register fsm)))
      (should (eq (my/gptel--fsm-get-by-id id) fsm)))))

(ert-deftest test-fsm/get-by-id-unknown ()
  (should-not (my/gptel--fsm-get-by-id "x")))

(ert-deftest test-fsm/get-id ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (let ((id (my/gptel--fsm-register fsm)))
      (should (equal (my/gptel--fsm-get-id fsm) id)))))

(ert-deftest test-fsm/get-id-unregistered ()
  (test-fsm-reset)
  (should-not (my/gptel--fsm-get-id (test-fsm-make))))

;; Count tests

(ert-deftest test-fsm/count-nil ()
  (should (= (my/gptel--fsm-count nil) 0)))

(ert-deftest test-fsm/count-one ()
  (test-fsm-reset)
  (should (= (my/gptel--fsm-count (test-fsm-make)) 1)))

(ert-deftest test-fsm/count-two ()
  (test-fsm-reset)
  (should (= (my/gptel--fsm-count (list (test-fsm-make) (test-fsm-make))) 2)))

;; Collect tests

(ert-deftest test-fsm/collect-nil ()
  (should (null (my/gptel--collect-all-fsms nil))))

(ert-deftest test-fsm/collect-one ()
  (test-fsm-reset)
  (should (= (length (my/gptel--collect-all-fsms (test-fsm-make))) 1)))

(ert-deftest test-fsm/collect-two ()
  (test-fsm-reset)
  (should (= (length (my/gptel--collect-all-fsms (list (test-fsm-make) (test-fsm-make)))) 2)))

;; Coerce tests

(ert-deftest test-fsm/coerce-direct ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (should (eq (my/gptel--coerce-fsm fsm) fsm))))

(ert-deftest test-fsm/coerce-nil ()
  (should-not (my/gptel--coerce-fsm nil)))

(ert-deftest test-fsm/coerce-list ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (should (eq (my/gptel--coerce-fsm (list 'x fsm 'y)) fsm))))

(ert-deftest test-fsm/coerce-context ()
  (test-fsm-reset)
  (let ((a (test-fsm-make)))
    (let ((b (test-fsm-make)))
      (should (eq (my/gptel--coerce-fsm-with-context (list a b)) b)))))

;; ID validation tests

(ert-deftest test-fsm/id-valid ()
  (should (my/gptel--fsm-id-valid-p "fsm-1-1234567890.123")))

(ert-deftest test-fsm/id-invalid ()
  (should-not (my/gptel--fsm-id-valid-p "x"))
  (should-not (my/gptel--fsm-id-valid-p nil)))

;; Registry validate tests

(ert-deftest test-fsm/validate-empty ()
  (test-fsm-reset)
  (should (my/gptel--fsm-registry-validate)))

(ert-deftest test-fsm/validate-unregistered ()
  (test-fsm-reset)
  (let ((fsm (test-fsm-make)))
    (let ((id (my/gptel--fsm-register fsm)))
      (my/gptel--fsm-unregister id)
      (should (my/gptel--fsm-registry-validate)))))

(provide 'test-gptel-ext-fsm-utils)