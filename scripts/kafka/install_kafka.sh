#!/bin/bash

# Check if IP and SSH key path are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <server_ip> <ssh_key_path>"
    exit 1
fi

SERVER_IP=$1
SSH_KEY_PATH=$2

echo "Installing Kafka in KRaft mode on $SERVER_IP using SSH key authentication"

# SSH command with key authentication
SSH_CMD="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no root@$SERVER_IP"

# Copy configuration files to a temporary directory
echo "Creating temporary directory for configuration files"
TMP_DIR=$(mktemp -d)
cp config/kafka/server.properties $TMP_DIR/
cp config/kafka/kafka.service $TMP_DIR/

# Replace placeholders with actual values
echo "Customizing configuration files for server $SERVER_IP"
sed -i "s/%SERVER_IP%/$SERVER_IP/g" $TMP_DIR/server.properties

# Copy configuration files to the server
echo "Copying configuration files to server $SERVER_IP"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no $TMP_DIR/server.properties root@$SERVER_IP:/tmp/server.properties
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no $TMP_DIR/kafka.service root@$SERVER_IP:/tmp/kafka.service

# Clean up temporary files
rm -rf $TMP_DIR

# Run installation on server
$SSH_CMD << EOF
    # Update system
    apt-get update -y
    apt-get upgrade -y

    # Install dependencies
    apt-get install -y openjdk-17-jdk wget tar

    # Create dedicated Kafka user
    useradd -m -s /bin/bash kafka

    # Install Kafka
    wget https://downloads.apache.org/kafka/3.7.0/kafka_2.13-3.7.0.tgz
    tar -xzf kafka_2.13-3.7.0.tgz
    mv kafka_2.13-3.7.0 /opt/kafka
    rm kafka_2.13-3.7.0.tgz
    
    # Create data directories for Kafka
    mkdir -p /opt/kafka/data
    chown -R kafka:kafka /opt/kafka
    
    # Copy server configuration
    cp /tmp/server.properties /opt/kafka/config/kraft/server.properties
    
    # Generate Cluster UUID and format storage
    CLUSTER_ID=\$(cd /opt/kafka && bin/kafka-storage.sh random-uuid)
    echo "Generated Kafka Cluster ID: \$CLUSTER_ID"
    
    # Format storage with generated cluster ID
    cd /opt/kafka && bin/kafka-storage.sh format -t \$CLUSTER_ID -c config/kraft/server.properties
    
    # Update service file with cluster ID
    sed "s/%CLUSTER_ID%/\$CLUSTER_ID/g" /tmp/kafka.service > /etc/systemd/system/kafka.service
    
    # Enable and start Kafka
    systemctl daemon-reload
    systemctl enable kafka
    systemctl start kafka
    sleep 10
    systemctl status kafka

    # Open ports
    ufw allow 9092/tcp
    ufw allow 19092/tcp
    ufw allow 9093/tcp
    
    echo "Waiting for Kafka to fully start..."
    sleep 20
    
    # Test Kafka installation by creating a test topic
    /opt/kafka/bin/kafka-topics.sh --create --topic test-topic --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092
    echo "Kafka test topic created successfully"
EOF

echo "Kafka KRaft installation completed on $SERVER_IP"
