(ns ov5.pipeline.daemon-test
  (:require [clojure.java.io :as io]
            [clojure.test :refer [deftest is testing]]
            [ov5.pipeline.daemon :as d]))

(defn- temp-file []
  (doto (java.io.File/createTempFile "hb-daemon" nil)
    (.deleteOnExit)))

(defn- file-stub [path->file]
  (fn [path]
    (get path->file path (java.io.File. path))))

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
    (let* [tmp (java.io.File/createTempFile "missing-findings-" ".edn")
           missing-findings (str tmp ".nonexistent")]
      (.delete tmp)
      (let [check-fn (fn [& _] :dead)
            emacsclient-fn (fn [] "fake-emacsclient")
            eval-fn (fn [& _] {:exit 0 :out "" :err ""})]
        (let [result (with-redefs [d/check-worker-daemon check-fn
                                   d/resolve-emacsclient emacsclient-fn
                                   d/run-emacsclient-eval eval-fn]
                       (d/wait-for-idle! {:action :test
                                          :socket-name "gtm-product-org"
                                          :findings-file missing-findings
                                          :max-wait-ms 60000
                                          :min-start-wait-ms 0
                                          :pipeline-start-time 0}))]
          (is (= :failed result)
              (format "wait-for-idle! researcher branch should return :failed; got %s" result)))))))

;; --- resolve-emacsclient ---

(deftest resolve-emacsclient-uses-valid-sh-path
  (testing "When command -v returns a path, it is used directly"
    (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "/usr/bin/emacsclient")]
      (is (= "/usr/bin/emacsclient" (d/resolve-emacsclient))))))

(deftest resolve-emacsclient-first-fallback-wins
  (testing "When command -v returns blank and first fallback exists, it is returned"
    (let [tmp (temp-file)]
      (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "")
                    io/file (file-stub {"/opt/homebrew/bin/emacsclient" tmp})]
        (is (= "/opt/homebrew/bin/emacsclient" (d/resolve-emacsclient)))))))

(deftest resolve-emacsclient-second-fallback-wins
  (testing "When first fallback missing, second fallback is returned"
    (let [tmp (temp-file)
          missing (java.io.File. "/definitely-missing-emacsclient")]
      (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "")
                    io/file (file-stub {"/opt/homebrew/bin/emacsclient" missing
                                        "/usr/local/bin/emacsclient" tmp})]
        (is (= "/usr/local/bin/emacsclient" (d/resolve-emacsclient)))))))

;; --- resolve-emacs ---

(deftest resolve-emacs-uses-valid-sh-path
  (testing "When command -v returns a path, it is used directly"
    (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "/usr/bin/emacs")]
      (is (= "/usr/bin/emacs" (d/resolve-emacs))))))

(deftest resolve-emacs-first-fallback-wins
  (testing "When command -v returns blank and first fallback exists, it is returned"
    (let [tmp (temp-file)
          missing (java.io.File. "/definitely-missing-emacs")]
      (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "")
                    io/file (file-stub {"/opt/homebrew/bin/emacs" tmp
                                        "/usr/local/bin/emacs" missing
                                        "/Applications/Emacs.app/Contents/MacOS/Emacs" missing})]
        (is (= "/opt/homebrew/bin/emacs" (d/resolve-emacs)))))))

(deftest resolve-emacs-second-fallback-wins
  (testing "When first fallback missing, second fallback is returned"
    (let [tmp (temp-file)
          missing (java.io.File. "/definitely-missing-emacs")]
      (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "")
                    io/file (file-stub {"/opt/homebrew/bin/emacs" missing
                                        "/usr/local/bin/emacs" tmp
                                        "/Applications/Emacs.app/Contents/MacOS/Emacs" missing})]
        (is (= "/usr/local/bin/emacs" (d/resolve-emacs)))))))

(deftest resolve-emacs-app-bundle-wins
  (testing "When both Homebrew paths are missing, the app bundle is returned"
    (let [tmp (temp-file)
          missing (java.io.File. "/definitely-missing-emacs")]
      (with-redefs [ov5.pipeline.process/sh-out (fn [& _] "")
                    io/file (file-stub {"/opt/homebrew/bin/emacs" missing
                                        "/usr/local/bin/emacs" missing
                                        "/Applications/Emacs.app/Contents/MacOS/Emacs" tmp})]
        (is (= "/Applications/Emacs.app/Contents/MacOS/Emacs" (d/resolve-emacs)))))))
