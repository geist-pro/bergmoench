#!/bin/sh
# Check out Anki's source (AGPL-3.0, https://github.com/ankitects/anki) at the commit this app is built against.
# kartei-core links Anki's Rust backend (rslib) from spike/anki; the checkout stays out of this repository.
set -eu
ANKI_COMMIT="827f4aa42681f1d60ab0fe4ad76eb75d767a385e"   # Anki 26.09.4
DEST="$(cd "$(dirname "$0")/../.." && pwd)/spike/anki"
if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$DEST"
  git -C "$DEST" init -q
  git -C "$DEST" remote add origin https://github.com/ankitects/anki.git
fi
git -C "$DEST" fetch -q --depth 1 origin "$ANKI_COMMIT"
git -C "$DEST" checkout -q "$ANKI_COMMIT"
git -C "$DEST" submodule update -q --init --depth 1
echo "Anki source at $ANKI_COMMIT in $DEST"
