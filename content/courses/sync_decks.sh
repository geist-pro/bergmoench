#!/bin/sh
# Fetch the course cards from the two public deck repositories into src/.
#   https://github.com/geist-pro/deck-programmieren        (cards: CC BY-SA 4.0)
#   https://github.com/geist-pro/deck-cooperation-systems  (cards: CC BY-SA 4.0)
# The copies stay out of git. DECKS_REF pins the release that ships with the app.
# For local work on the cards, point DECKS_DIR at a folder that holds both checkouts.
set -eu
DECKS_REF="${DECKS_REF:-v2026.11}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$SRC"
mkdir -p "$SRC/cards" "$SRC/figures" "$SRC/tools"
for repo in deck-programmieren deck-cooperation-systems; do
  if [ -n "${DECKS_DIR:-}" ]; then
    from="$DECKS_DIR/$repo"
  else
    git clone -q --depth 1 --branch "$DECKS_REF" "https://github.com/geist-pro/$repo.git" "$TMP/$repo"
    from="$TMP/$repo"
  fi
  cp -R "$from/cards/." "$SRC/cards/"
  cp "$from"/figures/*.png "$SRC/figures/"
  cp "$from/tools/cardlib.py" "$SRC/tools/"
done
echo "cards from ${DECKS_DIR:-geist-pro @ $DECKS_REF} are in $SRC"
