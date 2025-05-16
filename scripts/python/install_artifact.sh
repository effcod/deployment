#!/bin/bash
# install_artifact.sh for deploying a PyInstaller-built standalone executable.
# This script accepts two arguments:
#   1. The version of the artifact to deploy.
#   2. A command that will be passed to the executable as: --command <command>.
#
# Usage: ./install_artifact.sh <version> <command>
# Example: ./install_artifact.sh 0.0.3 quote_api_to_file

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version> <command>"
  exit 1
fi

VERSION=$1
ARTIFACT="trading-${VERSION}"
SOURCE_ARTIFACT="/tmp/$ARTIFACT"

TARGET_BASE_PATH="/opt/python-app"
TARGET_ARTIFACT="$TARGET_BASE_PATH/$ARTIFACT"

echo "Deploying standalone artifact version $VERSION with command '$COMMAND'..."
echo "  From: $SOURCE_ARTIFACT"
echo "  To:   $TARGET_ARTIFACT"

# Remove any existing artifact from /opt.
if [ -f "$TARGET_ARTIFACT" ]; then
  echo "Removing existing artifact $TARGET_ARTIFACT..."
  rm -f "$TARGET_ARTIFACT"
fi

echo "Moving artifact to $TARGET_ARTIFACT..."
mkdir -p "$TARGET_BASE_PATH"
mv "$SOURCE_ARTIFACT" "$TARGET_ARTIFACT"
cd "$TARGET_BASE_PATH"
chmod +x "$TARGET_ARTIFACT"

SYMBOL_SOURCE_PATH="/tmp/symbols.txt"
SYMBOL_TARGET_PATH="/opt/symbols"
mkdir -p "$SYMBOL_TARGET_PATH"
SYMBOL_TARGET_FILE="/opt/symbols/symbols-${VERSION}.txt"
mv "$SYMBOL_SOURCE_PATH" "$SYMBOL_TARGET_FILE"

SYMLINK="$SYMBOL_TARGET_PATH/symbols.txt"
# Remove the existing symbolic link if it exists
if [ -L "$SYMLINK" ]; then
    rm "$SYMLINK"
fi

# Create a new symbolic link to the latest version
ln -s "$SYMBOL_TARGET_FILE" "$SYMLINK"
ls -l $SYMBOL_TARGET_PATH
