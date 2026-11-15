#!/bin/bash
# Copies the dzz corpus (toc.txt + NN/*.txt) into the app bundle's Books/ folder.
# Excludes .git, README.md, TODO and anything else that is not a numbered volume.
set -euo pipefail

SRC="$SRCROOT/../dzz"
DST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books"

if [ ! -f "$SRC/toc.txt" ]; then
  echo "error: corpus not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DST"
rsync -a --delete \
  --include='toc.txt' \
  --include='[0-9][0-9]/' \
  --include='[0-9][0-9]/*.txt' \
  --exclude='*' \
  "$SRC/" "$DST/"

echo "Copied corpus: $(find "$DST" -name '*.txt' | wc -l | tr -d ' ') files"
