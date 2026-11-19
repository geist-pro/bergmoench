#!/bin/sh
# Copy the built course decks (out/course-*.apkg) into both apps.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
APPLE="$HERE/../../apps/apple/Kartei/Resources"
ANDROID="$HERE/../../apps/android/app/src/main/assets/courses"
mkdir -p "$ANDROID"
cp "$HERE"/out/course-*.apkg "$APPLE/"
cp "$HERE"/out/course-*.apkg "$ANDROID/"
ls -l "$APPLE"/course-*.apkg "$ANDROID"/course-*.apkg
