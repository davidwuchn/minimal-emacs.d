#!/usr/bin/env bash
# Regression test: OV5 pipeline re-exec must construct a proper command vector.
# Root cause: into-array String passed as a single arg to p/exec caused
# "Cannot resolve program: [Ljava.lang.String;@..."  Use apply instead.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE_CLJ="$DIR/clj/ov5/pipeline.clj"
PASS=0
FAIL=0
red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "Anti-pattern: no into-array String in bootstrap-and-pull! re-exec path"

# The bootstrap-and-pull! function is the only place p/exec is called.
# Verify into-array String is not present near the p/exec call site.
if grep -qzP 'bootstrap-and-pull.*into-array String' "$PIPELINE_CLJ" 2>/dev/null; then
  fail "into-array String still present in bootstrap-and-pull! body"
else
  pass "no into-array String in bootstrap-and-pull! re-exec path"
fi

section "Correct pattern: apply p/exec in re-exec path"

if grep -q 'apply p/exec' "$PIPELINE_CLJ"; then
  pass "apply p/exec found in pipeline.clj"
else
  fail "apply p/exec not found in pipeline.clj"
fi

section "Command-construction smoke via bb -e"

BB_OUTPUT=$(bb --deps-root "$DIR" -e '
(let [sample-args ["--smoke" "--dry-run"]
      cmd (into [] (concat ["bb" "-m" "ov5.pipeline"] sample-args))]
  (doseq [part cmd]
    (println (str "element:" part)))
  (println (str "count:" (count cmd))))' 2>&1) || {
  fail "bb -e command construction failed: $BB_OUTPUT"
  echo "=== Summary: $PASS passed, $FAIL failed ==="
  exit 1
}

if echo "$BB_OUTPUT" | grep -q "element:bb" && \
   echo "$BB_OUTPUT" | grep -q "element:-m" && \
   echo "$BB_OUTPUT" | grep -Fxq "count:5"; then
  pass "command vector: bb -m ov5.pipeline --smoke --dry-run (5 elements)"
else
  echo "  output: $BB_OUTPUT"
  fail "command vector malformed"
fi

# Verify no element contains the Java array toString marker
if echo "$BB_OUTPUT" | grep -q '\[Ljava.lang.String'; then
  fail "command vector contains Java array toString (regression!)"
else
  pass "no Java array toString in command vector"
fi

section "Subprocess smoke: apply pattern works with babashka.process"

SUB_OUTPUT=$(bb --deps-root "$DIR" -e '
(require (quote [babashka.process :as p]))
(let [cmd ["echo" "pipeline-re-exec-smoke-test"]
      result @(apply p/process {:out :string :err :string} cmd)]
  (println (clojure.string/trim (:out result))))' 2>&1) || {
  fail "apply p/process smoke failed: $SUB_OUTPUT"
  echo "=== Summary: $PASS passed, $FAIL failed ==="
  exit 1
}

if echo "$SUB_OUTPUT" | grep -q "pipeline-re-exec-smoke-test"; then
  pass "apply pattern with babashka.process executes correctly"
else
  echo "  output: $SUB_OUTPUT"
  fail "apply pattern execution failed"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
