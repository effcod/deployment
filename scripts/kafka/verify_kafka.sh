#!/bin/bash
SERVER_IP=$1
ROOT_PASSWORD=$2

echo "Verifying Kafka installation on $SERVER_IP"

sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$SERVER_IP << EOF
    # Check if Kafka service is running
    echo "Checking Kafka service status..."
    systemctl status kafka | grep "active (running)"
    if [ $? -ne 0 ]; then
        echo "ERROR: Kafka service is not running"
        exit 1
    fi
    
    # Check if Kafka ports are listening
    echo "Checking if Kafka ports are open..."
    netstat -plnt | grep 9092
    if [ $? -ne 0 ]; then
        echo "ERROR: Kafka is not listening on port 9092"
        exit 1
    fi
    
    # Create a test topic
    echo "Creating test topic..."
    /opt/kafka/bin/kafka-topics.sh --create --topic verify-topic --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092
    
    # List topics to verify
    echo "Listing topics..."
    /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
    
    # Produce a test message
    echo "Producing test message..."
    echo "Test message" | /opt/kafka/bin/kafka-console-producer.sh --topic verify-topic --bootstrap-server localhost:9092
    
    # Consume the test message with timeout
    echo "Consuming test message..."
    timeout 10s /opt/kafka/bin/kafka-console-consumer.sh --topic verify-topic --from-beginning --bootstrap-server localhost:9092 --max-messages 1
    
    # Check if Kafka logs show startup success
    echo "Checking Kafka logs for successful startup..."
    grep -i "started" /opt/kafka/logs/server.log | tail -5
    
    echo "Kafka verification completed successfully"
EOF

if [ $? -eq 0 ]; then
    echo "✅ Kafka is running correctly on $SERVER_IP"
    exit 0
else
    echo "❌ Kafka verification failed on $SERVER_IP"
    exit 1
fi
