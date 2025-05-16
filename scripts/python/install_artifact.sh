#!/bin/bash
# install_artifact.sh for deploying a PyInstaller-built standalone executable.
# This script accepts two arguments:
#   1. The version of the artifact to deploy.
#   2. A command that will be passed to the executable as: --command <command>.
#
# Usage: ./install_artifact.sh <version> <command>
# Example: ./install_artifact.sh 0.0.3 quote_api_to_file

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <command>"
  exit 1
fi

VERSION=$1
COMMAND=$2
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

# Optionally, kill any existing running instance of the old version.
# For example: pkill -f "$TARGET_ARTIFACT" || true

# Ensure the artifact has executable permissions.
chmod +x "$TARGET_ARTIFACT"

# Launch the standalone executable in the background, passing the command argument.
nohup "$TARGET_ARTIFACT" --command "$COMMAND" > "/opt/trading-${VERSION}.log" 2>&1 &

echo "Deployment completed. Application is running; check /opt/trading-${VERSION}.log for logs."
