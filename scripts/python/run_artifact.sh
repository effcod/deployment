#!/bin/bash
#
# run_artifact.sh: Run the deployed Python app artifact with a given command.
#
# Usage:
#   ./run_artifact.sh <version> <command>
#
# Example:
#   ./run_artifact.sh 0.0.3 --command quote_api_to_kafka
#
# This script assumes that the artifact "trading-<version>" exists in /opt/python-app.
#

# Ensure exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <command>"
    exit 1
fi

VERSION="$1"
COMMAND="$2"
ARTIFACT="/opt/python-app/trading-${VERSION}"

# Verify that the artifact file exists
if [ ! -f "$ARTIFACT" ]; then
    echo "Error: Artifact file '$ARTIFACT' not found."
    exit 1
fi

# Ensure the artifact is executable
chmod +x "$ARTIFACT"

# Change to the /opt/python-app directory
cd /opt/python-app || { echo "Error: Cannot change directory to /opt/python-app"; exit 1; }

# Define the start time with date and time down to seconds for a unique log filename
start_time=$(date +'%Y-%m-%d-%H-%M-%S')
LOGFILE="/opt/trading-${VERSION}-${start_time}.log"
echo "Artifact started on: ${start_time}" > "$LOGFILE"

echo "Starting artifact '${ARTIFACT}' with command '$COMMAND'..."
echo "Logs will be written to '$LOGFILE'."

# Run the artifact in the background using nohup so it survives the SSH session.
nohup "$ARTIFACT" $COMMAND >> "$LOGFILE" 2>&1 &
