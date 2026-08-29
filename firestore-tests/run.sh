#!/usr/bin/env bash
# Runs the rules suite against a throwaway Firestore emulator.
#
# The only thing this adds over calling `firebase emulators:exec` directly is
# finding Java. The Firestore emulator is a Java process, and macOS ships a
# `/usr/bin/java` **stub** that isn't a runtime — it exists only to open the
# "install Java" page. So `java -version` succeeds as a command and fails as a
# runtime, and `firebase` reports it as "exited with code 1", which sends you
# looking at the emulator rather than at the JDK.
#
# `brew install openjdk` is keg-only: it deliberately does not shadow that stub,
# so nothing on PATH changes and no shell profile was edited to make this work.
# Pointing JAVA_HOME at it here is what keeps `npm run test:rules` self-
# contained — and an already-set JAVA_HOME wins, for anyone who has their own.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${JAVA_HOME:-}" ]]; then
  if brew_openjdk="$(brew --prefix openjdk 2>/dev/null)" \
    && [[ -d "$brew_openjdk/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="$brew_openjdk/libexec/openjdk.jdk/Contents/Home"
  fi
fi

if ! "${JAVA_HOME:-/usr}/bin/java" -version >/dev/null 2>&1; then
  echo "No Java runtime. The Firestore emulator needs one:" >&2
  echo >&2
  echo "    brew install openjdk" >&2
  echo >&2
  echo "(keg-only — it won't become this machine's default java)." >&2
  exit 1
fi

export PATH="$JAVA_HOME/bin:$PATH"

# Node's test runner takes file paths, not a bare directory — handed one it
# tries to `require` it as a module. The glob is what makes `--test` discover
# the suite, and any argument passed to this script narrows it to one file.
TARGET="${1:-firestore-tests/*.test.mjs}"

exec npx firebase emulators:exec \
  --only firestore \
  --project hoopsrn-test \
  "node --test $TARGET"
