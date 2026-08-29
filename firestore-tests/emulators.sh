#!/usr/bin/env bash
# Keeps a Firestore emulator up so `node --test firestore-tests/` can be run
# repeatedly against it. Same Java resolution as `run.sh` — see the comment
# there for why macOS's `/usr/bin/java` isn't one.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${JAVA_HOME:-}" ]]; then
  if brew_openjdk="$(brew --prefix openjdk 2>/dev/null)" \
    && [[ -d "$brew_openjdk/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="$brew_openjdk/libexec/openjdk.jdk/Contents/Home"
  fi
fi

export PATH="${JAVA_HOME:-/usr}/bin:$PATH"

exec npx firebase emulators:start --only firestore --project hoopsrn-test
