# Quick Reference Examples

Quick references are created when search patterns repeat frequently.

## 💡 Threading Quick Reference

Created after 10+ searches for "threading macros"

```clojure
;; -> for objects (threading into first position)
(-> user
    (assoc :name "Alice")
    (update :age inc))
;; Same as: (update (assoc user :name "Alice") :age inc)

;; ->> for collections (threading into last position)
(->> numbers
     (filter odd?)
     (map inc)
     (reduce + 0))
;; Same as: (reduce + 0 (map inc (filter odd? numbers)))

;; some-> for nil-safe operations
(some-> user
        :profile
        :settings
        :theme)
;; Returns nil if any intermediate value is nil

;; cond-> for conditional threading
(cond-> data
  should-validate (validate)
  should-transform (transform))
```

---

## 💡 File Operations Quick Reference

Created after 8+ searches for "file operations opencode"

```bash
# Search: Find files by pattern
glob "**/*.clj"
glob "src/**/*.ts"

# Search: Find content by regex
grep "function.*test"
grep "defn.*handler" --include="*.clj"

# Read: File operations
read path/to/file.md
read path/to/file 1 10  # offset, limit

# Edit: Precise edits
edit path/to/file.md
  oldString: "old text"
  newString: "new text"

# Write: Create/overwrite files
write content path/to/file.md

# Always grep before edit (grep-before-edit instinct)
```

---

## 💡 Naming Conventions Quick Reference

Created after 12+ searches for "naming conventions"

```clojure
;; Files: kebab-case
user-profile-handler.clj
api-endpoint.ts

;; Functions: kebab-case, verb-noun
get-user-by-id
create-api-endpoint
update-user-settings

;; Predicates: ? suffix
valid-user?
active-account?
has-permissions?

;; Conversions: -> infix
user->dto
json->map
string->keyword

;; Constants: screaming snake case
MAX_RETRIES
DEFAULT_TIMEOUT
API_ENDPOINT_URL

;; Private functions: - suffix
-internal-helper
-validate-input
```

---

## 💡 Testing Quick Reference

Created after 15+ searches for "testing patterns"

```clojure
;; Test-first instinct: RED → GREEN → IMPROVE

;; 1. RED: Write failing test
(deftest test-add
  (is (= 5 (add 2 2))))  ; Fails

;; 2. GREEN: Make test pass
(defn add [a b] (+ a b))

;; 3. IMPROVE: Refactor if needed
(defn add [a b]
  {:pre [(number? a) (number? b)]}
  (+ a b))

;; Use are for multiple test cases
(deftest test-multiplication
  (are [x y expected]
    (= (multiply x y) expected)
    2 3 6
    0 5 0
    -2 3 -6))

;; Use testing for context
(deftest test-string-operations
  (testing "concatenation"
    (is (= "hello world" (str "hello " "world"))))

  (testing "uppercase"
    (is (= "HELLO" (clojure.string/upper-case "hello")))))
```

---

## How Quick References Are Created

When a pattern is searched for repeatedly (>5 times):
1. Detect search pattern in session logs
2. Analyze relevance (high access frequency)
3. Create quick reference file
4. Add to top of relevant instinct section
5. Result: O(1) access without search

---

**Quick references eliminate search friction for frequently accessed patterns.**
