#!/bin/bash
# install_artifact.sh for deploying a zipapp.
# This script accepts one argument: the version of the artifact to deploy.

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

VERSION=$1
ARTIFACT="trading-${VERSION}.pyz"
SOURCE_ARTIFACT="/tmp/$ARTIFACT"

TARGET_BASE_PATH="/opt/python-app"
TARGET_ARTIFACT="$TARGET_BASE_PATH/$ARTIFACT"

echo "Deploying zipapp version $VERSION..."
echo "  From: $SOURCE_ARTIFACT"
echo "  To: $TARGET_ARTIFACT"

# Remove any existing artifact from /opt
if [ -f "$TARGET_ARTIFACT" ]; then
  echo "Removing existing artifact $TARGET_ARTIFACT..."
  rm -f "$TARGET_ARTIFACT"
fi

echo "Moving artifact to $TARGET_ARTIFACT..."
mkdir -p "$TARGET_BASE_PATH"
mv "$SOURCE_ARTIFACT" "$TARGET_ARTIFACT"
cd "$TARGET_BASE_PATH"
# Optionally, kill any existing running instance of the old version.
# For example: pkill -f "python3 $APP_PATH" || true

# Launch the zipapp in the background. This will execute the bundled __main__.py.
nohup python3 "$TARGET_ARTIFACT" > "/opt/trading-${VERSION}.log" 2>&1 &

echo "Deployment completed. Application is running; check /opt/trading-${VERSION}.log for logs."
