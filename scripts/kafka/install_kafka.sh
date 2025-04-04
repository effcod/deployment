#!/bin/bash

set -e

# Constants
KAFKA_VERSION="3.8.0"
KAFKA_INSTALL_DIR="/opt/kafka_2.13-$KAFKA_VERSION"
KAFKA_SYMLINK="/opt/kafka"
KAFKA_USER="kraft"

# Validation: Check if required files exist
echo "Validating required configuration files..."
if [[ ! -f /tmp/server.properties ]]; then
  echo "Error: /tmp/server.properties file is missing!"
  exit 1
fi

if [[ ! -f /tmp/kafka.service ]]; then
  echo "Error: /tmp/kafka.service file is missing!"
  exit 1
fi
echo "All required files are present."

# Step 1: Update package list and install dependencies
echo "Updating package list and installing required packages..."
sudo apt update && sudo apt install -y default-jre default-jdk wget tar
echo "Dependencies installed successfully."

# Step 2: Create Kafka user
echo "Creating '$KAFKA_USER' user (no login)..."
sudo useradd -m $KAFKA_USER -s /usr/sbin/nologin || echo "User '$KAFKA_USER' already exists."
echo "User '$KAFKA_USER' created or already exists."

# Step 3: Download and Extract Kafka
echo "Downloading Kafka $KAFKA_VERSION..."
cd /opt/
sudo wget https://dlcdn.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz -O kafka.tgz
echo "Extracting Kafka..."
sudo tar xzf kafka.tgz
sudo rm kafka.tgz
echo "Kafka extracted to $KAFKA_INSTALL_DIR."

# Step 4: Create Symbolic Link
if [[ -L $KAFKA_SYMLINK ]]; then
  echo "Removing old symbolic link..."
  sudo rm $KAFKA_SYMLINK
fi
echo "Creating new symbolic link $KAFKA_SYMLINK -> $KAFKA_INSTALL_DIR..."
sudo ln -s $KAFKA_INSTALL_DIR $KAFKA_SYMLINK
echo "Symbolic link created successfully."

cd $KAFKA_SYMLINK
echo "Backup old server.properties file"
sudo cp config/kraft/server.properties config/kraft/server.properties.backup

# Step 5: Move Provided Configuration Files
echo "Moving server.properties and kafka.service to their respective directories..."
sudo mv /tmp/server.properties $KAFKA_SYMLINK/config/kraft/server.properties
sudo mv /tmp/kafka.service /lib/systemd/system/kafka.service
echo "Configuration files moved successfully."

# Step 6: Kafka Kraft Setup
echo "Formatting Kafka storage with Cluster ID..."
export KAFKA_CLUSTER_ID="$(bin/kafka-storage.sh random-uuid)"
echo "Generated Kafka Cluster ID: $KAFKA_CLUSTER_ID"
sudo bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -c config/kraft/server.properties
echo "Kafka storage formatted successfully."

# Step 7: Set permissions for Kafka directory
echo "Setting permissions for Kafka directory..."
sudo chown -R $KAFKA_USER:$KAFKA_USER $KAFKA_INSTALL_DIR
echo "Permissions set successfully."

# Step 8: Start Kafka Service
echo "Starting Kafka service..."
sudo systemctl daemon-reload
sudo systemctl enable kafka.service
sudo systemctl start kafka.service
echo "Kafka service started and enabled."

# Step 9: Verify Kafka Service Status
echo "Verifying Kafka service status..."
sudo systemctl status kafka.service --no-pager || echo "Warning: Kafka service may not be running."
echo "Kafka Kraft installation and configuration completed successfully!"

echo "Testing Kafka logs..."
sudo tail -n 50 $KAFKA_SYMLINK/logs/server.log || echo "Warning: Unable to display logs."

echo "Kafka Kraft node is now running on localhost:9092 with a symbolic link at $KAFKA_SYMLINK."
