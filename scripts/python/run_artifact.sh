#!/bin/bash
#
# run_artifact.sh: Run the deployed artifact with a given command.
#
# Usage:
#   ./run_artifact.sh <version> <command>
#
# Example:
#   ./run_artifact.sh 0.0.3 --command quote_api_to_kafka
#
# This script assumes that the artifact "trading-<version>" exists in /opt/python-app.

# Check that exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <version> <command>"
    exit 1
fi

VERSION="$1"
COMMAND="$2"
ARTIFACT="/opt/python-app/trading-${VERSION}"

# Verify the artifact exists
if [ ! -f "$ARTIFACT" ]; then
    echo "Error: Artifact file '$ARTIFACT' not found."
    exit 1
fi

# Ensure the artifact is executable
chmod +x "$ARTIFACT"

# Change to the /opt/python-app directory
cd /opt/python-app || { echo "Error: Cannot change directory to /opt/python-app"; exit 1; }

# Define log file location
LOGFILE="/tmp/trading-${VERSION}.log"

echo "Starting artifact '${ARTIFACT}' with command '$COMMAND'..."
echo "Logs will be written to '$LOGFILE'."

# Run the artifact in the background using nohup so it survives the SSH session.
nohup "$ARTIFACT" "$COMMAND" > "$LOGFILE" 2>&1 &

# Capture the process ID (PID) of the background process.
PID=$!
echo "Artifact started with PID $PID."

# Write the PID to a file in the /opt folder.
PID_FILE="/opt/trading-${VERSION}.pid"
echo "$PID" > "$PID_FILE"
echo "PID file written to '$PID_FILE'."
