(ns ov5.pipeline.log-test
  (:require [clojure.test :refer [deftest is testing]]
            [ov5.pipeline.log :as log]))

;; Regression test for the logf character-splitting bug.
;;
;; The old logf was (apply log (apply format fmt args)).  When format
;; returns a String and log is variadic, `apply log <string>` spreads
;; the string into individual characters, so the resulting log line
;; was "v a l" instead of "val".
;;
;; The fix is (log (apply format fmt args)) which passes the formatted
;; string as a single argument.

(deftest logf-passes-formatted-string-as-single-arg
  (testing "logf calls log with the formatted string as ONE argument"
    (let [captured (atom nil)]
      (with-redefs [log/log (fn [& args]
                              (reset! captured args)
                              nil)]
        (log/logf "thing: %s" "val"))
      (is (= 1 (count @captured))
          "logf must pass the formatted string as a single arg, not split chars")
      (is (= "thing: val" (first @captured))
          "logf should pass the formatted string to log"))))

(deftest logf-with-plain-string
  (testing "logf with literal string (no %s, no args) is one arg"
    (let [captured (atom nil)]
      (with-redefs [log/log (fn [& args]
                              (reset! captured args)
                              nil)]
        (log/logf "hello"))
      (is (= 1 (count @captured))
          "logf with plain string must pass it as single arg, not split chars")
      (is (= "hello" (first @captured))))))

(deftest logf-with-multiple-format-args
  (testing "logf with multiple %s placeholders is still a single string arg"
    (let [captured (atom nil)]
      (with-redefs [log/log (fn [& args]
                              (reset! captured args)
                              nil)]
        (log/logf "%s and %s" "foo" "bar"))
      (is (= 1 (count @captured)))
      (is (= "foo and bar" (first @captured))))))
