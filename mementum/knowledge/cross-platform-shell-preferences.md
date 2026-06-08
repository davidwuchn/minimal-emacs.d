---
name: cross-platform-shell-preferences
description: Perl5 + ack for cross-platform (macOS + Linux) shell scripting — avoid sed/grep BSD vs GNU traps
version: 1.0
---

# Cross-Platform Shell Preferences

## Why

macOS ships BSD `sed` and BSD `grep`; Linux ships GNU versions. They have
incompatible flags and behaviors:

| Operation              | GNU (Linux)        | BSD (macOS)            | Cross-platform fix |
|------------------------|--------------------|------------------------|--------------------|
| In-place edit          | `sed -i 's/x/y/'`  | `sed -i '' 's/x/y/'`   | `perl -pi -e 's/x/y/'` |
| Print matching lines   | `sed -n '/p/p'`    | works, but watch BRE/ERE | `perl -ne 'print if /p/'` |
| PCRE `-P` flag         | `grep -oP 'pat'`   | NOT available          | `perl -ne 'print $1 if /pat/'` |
| Per-line scripting     | `awk '/pat/{...}'` | same, but split(awk)   | `perl -ne '...'`    |
| Recursive code search  | `grep -rn 'pat' .` | same, but ignores .git | `ack 'pat'` (skips .git, .elc, var/) |

`perl5` ships on every macOS by default and on every Linux. Behavior is
identical. `ack` is a Perl-based `grep` replacement designed for source
code (skips .git, .elc, var/, binary files by default; better defaults
than `grep -r` for codebases).

## When to use what

- **Quick text substitution in one file** → `perl -pi -e 's/old/new/' file`
- **Extract capture group from each line** → `perl -ne 'print $1 if /pat/'`
- **Multi-line regex** → `perl -0777 -ne '...'` (slurp mode)
- **Recursive source code search** → `ack 'pattern'` (better than `grep -r`)
- **Recursive test for presence** → `ack -q 'pattern' file` (exit code)
- **BSD-sed feature used by ops/install scripts** → use `perl -pi -e` instead
  of building a BSD sed compatibility wrapper

## Concrete conversions

### sed -i (GNU) vs sed -i '' (BSD) → perl -pi -e

```bash
# BAD (Linux only):
sed -i 's/foo/bar/' file.txt
# BAD (macOS only):
sed -i '' 's/foo/bar/' file.txt
# GOOD (both):
perl -pi -e 's/foo/bar/' file.txt
```

### grep -oP (GNU only) → perl -ne

```bash
# BAD on macOS:
ids=$(grep -oP 'id:\s*\K\d+' file.tsv)
# GOOD:
ids=$(perl -ne 'print $1 if /id:\s*(\d+)/' file.tsv)
```

### sed -n '/pat/p' → perl -ne 'print if /pat/'

```bash
# Works on both, but perl is more predictable for complex regex:
perl -ne 'print if /phase "(idle|complete)"/' "$status"
```

### grep -r for source code → ack

```bash
# BAD (slow, includes .git, .elc, var/):
grep -rn 'TODO' lisp/ | head
# GOOD (fast, skips junk):
ack 'TODO' lisp/ | head
```

## Detection (when reviewing scripts)

Search for these patterns and replace:

- `sed -i` (without `''` after) → `perl -pi -e`
- `sed -i ''` → `perl -pi -e`
- `grep -oP` → `perl -ne 'print $1 if /.../'`
- `grep -E` for simple pattern → `ack -Q` or `perl -ne 'print if /.../'`
- `grep -r` in lisp/tests/ → `ack`
- `sed 's/.../.../'` in-place workflows → `perl -pi -e`
- `awk '/pat/{print}'` for simple cases → `perl -ne 'print if /pat/'`

## Verified cross-platform

- ✅ `perl -pi -e` — works on macOS and Linux (perldoc perlrun)
- ✅ `perl -ne` — works on macOS and Linux
- ✅ `ack` — Perl-based, ships on Homebrew, identical behavior

## Exceptions

Some operations are still better in their native tool:
- `find` (with `-newer`, `-path`) — same on both
- `git` — same on both
- `jq` — same on both
- `awk` — same on both (but `perl -ne` is often simpler)

## Reference

- `man perlrun` — perl command-line flags
- `man ack` — ack options
- `perldoc -q 'Why is this here\?'` — perl philosophy

## Long-term direction: rewrite shell scripts in perl5

Bash is fine for short glue (a few lines). For anything larger, prefer a
single-file perl5 script with `#!/usr/bin/env perl` shebang. Perl:

- Runs identically on macOS and Linux (no BSD/GNU fork)
- Has a real standard library (file I/O, JSON, HTTP, process management)
- Compiles to a syntax tree at startup — syntax errors caught at run
- Handles strings, regex, and data structures natively (no `awk | sed | tr`)
- Plays well with `prove` for testing

### Decision tree

| Script size       | Tool of choice                          |
|-------------------|------------------------------------------|
| 1–10 lines        | bash inline                              |
| 10–50 lines       | perl one-liner (`perl -ne '...'`)        |
| 50–200 lines      | perl one-liner or `.pl` script           |
| 200+ lines        | full `.pl` script                        |
| Needs JSON, HTTP  | perl with `JSON::PP` (core), `LWP` (core)|

### Step-by-step migration

When touching a bash script:

1. **If <10 lines and one-shot**: leave it in bash
2. **If 10–50 lines with non-trivial text processing**: convert inline to
   `perl -ne '...'` or `perl -i -pe '...'`
3. **If 50+ lines OR has bugs OR needs to grow**: rewrite as a `.pl` script
   with proper `use strict; use warnings;` and `Getopt::Long` for args
4. **If it grew from a one-liner**: refactor the one-liner into a `.pl`
   only when adding a second feature — premature rewrites waste tokens

### When NOT to convert

- Glue that wraps a single `git`, `docker`, or `kubectl` command
- Scripts that exit immediately on success (use bash; perl startup is
  ~3× slower for trivial cases)
- Anything that heavily depends on bash process substitution `<()` or
  arrays (perl5 doesn't have native arrays of arbitrary types; use AoH)

### Conversion helpers

- `bash $((x+1))` → `perl -e '$x+1'` or use `vars` in script
- `bash ${var//old/new}` → `perl s/old/new/`
- `bash [[ "$x" =~ pat ]]` → `perl $x =~ /pat/`
- `bash set -e` → `perl use autodie;` (or manual error checks)
- `bash trap 'cleanup' EXIT` → `perl END { cleanup() }`
- `bash getopts` → `perl Getopt::Long`

### Test pattern for perl scripts

Use `prove` with `.t` files, or shell out to perl from existing bash
tests (since `perl -e 'exit 0'` exits cleanly). The key invariant:
**a perl script called with no args or wrong args must exit non-zero
and print a usage message**. This is what bash `set -u` + `set -e` give
you for free; in perl you write it explicitly.
