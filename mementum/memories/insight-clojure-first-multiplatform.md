# Clojure-First Multi-Platform Architecture

**Context:** Studied [clojure.cc](https://clojure.cc/) — catalog of 39 Clojure dialects targeting every major platform (JVM, JS, Go, C/C++, Python, Rust, Erlang, .NET, Dart, PHP, Wasm, Lua, etc.).

**Key insight:** OV5 can use Clojure as its single experiment language and reach every platform through dialects. Instead of N per-language test/lint/deploy backends, one Clojure toolchain serves all platforms. OV5 already has brepl, Datahike, clojure.test runner, clj-kondo linter, and ns-ordering fixer in Clojure.

**Strategic decision:** Clojure-first eliminates the per-language backend scaling problem. Write `.clj`, test via clojure.test, lint via clj-kondo, transpile to target dialect, deploy to any platform.

**Full analysis:** `mementum/knowledge/clojure-first-multiplatform-architecture.md`

**Symbol:** 💡
