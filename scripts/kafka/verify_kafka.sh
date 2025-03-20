#!/bin/bash

# Check if IP and SSH key path are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <server_ip> <ssh_key_path>"
    exit 1
fi

SERVER_IP=$1
SSH_KEY_PATH=$2

echo "Verifying Kafka installation on $SERVER_IP"

# SSH command with key authentication
SSH_CMD="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no root@$SERVER_IP"

# Check if Kafka service is running
$SSH_CMD "systemctl is-active --quiet kafka" && echo "Kafka service is running" || echo "Kafka service is not running"

# Verify Kafka is properly functioning by listing topics
echo "Listing Kafka topics:"
$SSH_CMD "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"

# Check if our test topic exists
TEST_TOPIC=$($SSH_CMD "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 | grep test-topic")
if [ -n "$TEST_TOPIC" ]; then
    echo "Test topic exists. Kafka appears to be working properly."
else
    echo "Test topic not found. There might be an issue with the Kafka installation."
    exit 1
fi

echo "Kafka verification completed successfully on $SERVER_IP"
