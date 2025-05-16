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

# Define the start date and the log file location in /opt (with date included)
start_date=$(date +'%Y-%m-%d')
LOGFILE="/opt/trading-${VERSION}-${start_date}.log"
echo "Artifact started on: $start_date" > "$LOGFILE"

echo "Starting artifact '${ARTIFACT}' with command '$COMMAND'..."
echo "Logs will be written to '$LOGFILE'."

# Run the artifact in the background using nohup so it survives the SSH session.
nohup "$ARTIFACT" $COMMAND >> "$LOGFILE" 2>&1 &
initial_pid=$!
echo "Initial PID captured: $initial_pid"

# Wait briefly to allow the process to potentially fork (if daemonizing)
sleep 1

# Check if a child process exists (which would be the real daemonized app)
child_pid=$(ps --no-headers -o pid --ppid $initial_pid | head -n 1 | tr -d '[:space:]')

if [ -n "$child_pid" ]; then
    PID=$child_pid
    echo "Detected forked child process. Using child PID: $PID"
else
    PID=$initial_pid
    echo "No child process detected. Using initial PID: $PID"
fi

# Write the PID to a file named as <PID>.pid in /opt.
PID_FILE="/opt/${PID}.pid"
echo "$PID" > "$PID_FILE"
echo "PID file written to '$PID_FILE'."
