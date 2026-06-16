(ns ov5.pipeline.git-test
  (:require [clojure.test :refer [deftest is testing]]
            [ov5.pipeline.git :as g]))

;; only-auto-gen-paths? checks if all paths in PATHS are in auto-gen-dirs.
;; It uses str/starts-with? with each auto-gen dir.

(deftest only-auto-gen-paths-empty-list-returns-true
  ;; (every? ...) on empty list returns true.
  (testing "Empty path list returns true (vacuous truth)"
    (is (true? (g/only-auto-gen-paths? [])))))

(deftest only-auto-gen-paths-single-auto-gen
  (testing "Single path in auto-gen dir returns true"
    (is (true? (g/only-auto-gen-paths? ["mementum/knowledge/foo.md"])))))

(deftest only-auto-gen-paths-single-non-auto-gen
  (testing "Single path NOT in auto-gen dir returns false"
    (is (false? (g/only-auto-gen-paths? ["lisp/modules/foo.el"])))))

(deftest only-auto-gen-paths-mixed
  (testing "Mix of auto-gen and non-auto-gen returns false"
    (is (false? (g/only-auto-gen-paths? ["mementum/knowledge/foo.md" "lisp/modules/foo.el"])))))

(deftest only-auto-gen-paths-all-auto-gen
  (testing "All paths in auto-gen dirs returns true"
    (is (true? (g/only-auto-gen-paths? ["mementum/knowledge/a.md" "mementum/memories/b.md"
                                          "assistant/skills/c.md"])))))

(deftest only-auto-gen-paths-includes-state-md
  (testing "mementum/state.md is recognized as auto-generated"
    (is (true? (g/only-auto-gen-paths? ["mementum/state.md"])))))

(deftest only-auto-gen-paths-state-md-mixed-with-code-false
  (testing "state.md mixed with code file is not only auto-gen"
    (is (false? (g/only-auto-gen-paths? ["mementum/state.md" "lisp/modules/foo.el"])))))
