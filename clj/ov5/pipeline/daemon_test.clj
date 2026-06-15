(ns ov5.pipeline.daemon-test
  (:require [clojure.test :refer [deftest is testing]]
            [ov5.pipeline.daemon :as d]))

;; Regression tests for wait-for-idle!
;;
;; Original bug: the function always fell through to (Thread/sleep)+(recur),
;; discarding the :complete/:failed/:timeout keywords from inner branches.
;; With the OLD bug, the only way wait-for-idle! would return a non-nil
;; terminal value was via the timeout branch, even when the daemon had
;; actually finished.
;;
;; Fix: only recur on :continue-pm-loop/nil.  Return the terminal keyword
;; promptly so callers see it (and the wait ends in seconds, not the
;; 15min default max-wait-ms).

(deftest wait-for-idle-returns-timeout-when-elapsed-exceeds-max
  (testing "wait-for-idle! returns :timeout (not nil) when elapsed >= max-wait-ms"
    ;; This proves the function has a non-nil return path.
    (let [result (d/wait-for-idle! {:action :test
                                    :max-wait-ms 0
                                    :min-start-wait-ms 0
                                    :pipeline-start-time 0})]
      (is (= :timeout result)
          "wait-for-idle! should return :timeout, not nil"))))

(deftest wait-for-idle-researcher-branch-returns-failed-when-daemon-dies
  (testing "researcher branch returns :failed when daemon is dead and findings missing"
    ;; Behavior 2: gtm-product-org — when the daemon is not alive and
    ;; findings file doesn't exist, return :failed (promptly).
    ;; The OLD bug would discard this and run to :timeout.
    (let [result (with-redefs [d/check-worker-daemon (fn [& _] :dead)
                               d/resolve-emacsclient (fn [] "fake-emacsclient")
                               d/run-emacsclient-eval (fn [& _] {:exit 0 :out "" :err ""})]
                   (d/wait-for-idle! {:action :test
                                      :socket-name "gtm-product-org"
                                      :max-wait-ms 60000    ; 60s budget
                                      :min-start-wait-ms 0
                                      :pipeline-start-time 0}))]
      (is (= :failed result)
          (format "wait-for-idle! researcher branch should return :failed; got %s" result)))))
