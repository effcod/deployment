#!/bin/bash

# Kafka Infrastructure Status Script
# Checks brokers, topics list with partitions, and general health

KAFKA_PATH="/opt/kafka"

# Create metrics directory and file for data sharing
mkdir -p /tmp/monitor
METRICS_FILE="/tmp/monitor/kafka_metrics.txt"
> "$METRICS_FILE"  # Clear the file

echo "==============================================================================="
echo "                   KAFKA INFRASTRUCTURE STATUS"
echo "==============================================================================="
echo "Timestamp: $(date)"
echo "==============================================================================="

# Function to print formatted headers
print_header() {
    echo ""
    echo "--- $1 ---"
}

# Function to print separator
print_separator() {
    echo "-------------------------------------------------------------------------------"
}

# Function to save metrics
save_metric() {
    echo "$1=$2" >> "$METRICS_FILE"
}

# Check if Kafka is running
print_header "KAFKA SERVICE STATUS"
echo "Checking Kafka processes:"
KAFKA_PIDS=$(ps aux | grep -E "kafka\.Kafka|kafka\.server|org\.apache\.kafka" | grep -v grep | awk '{print $2}')

if [ -n "$KAFKA_PIDS" ]; then
    KAFKA_RUNNING="true"
    KAFKA_PROCESS_COUNT=$(echo "$KAFKA_PIDS" | wc -l)
    
    # Get Kafka memory usage
    KAFKA_MEMORY_TOTAL=0
    for pid in $KAFKA_PIDS; do
        if [ -f "/proc/$pid/status" ]; then
            KAFKA_MEM_KB=$(grep VmRSS /proc/$pid/status | awk '{print $2}')
            KAFKA_MEMORY_TOTAL=$((KAFKA_MEMORY_TOTAL + KAFKA_MEM_KB))
        fi
    done
    KAFKA_MEMORY_MB=$((KAFKA_MEMORY_TOTAL / 1024))
    
    save_metric "KAFKA_RUNNING" "$KAFKA_RUNNING"
    save_metric "KAFKA_PROCESS_COUNT" "$KAFKA_PROCESS_COUNT"
    save_metric "KAFKA_MEMORY_MB" "$KAFKA_MEMORY_MB"
    
    echo "✅ Kafka is running"
    echo "Kafka processes:"
    ps aux | grep -E "kafka\.Kafka|kafka\.server|org\.apache\.kafka" | grep -v grep | \
    awk '{printf "  PID: %-8s User: %-8s CPU: %-6s MEM: %-6s Start: %-8s\n", $2, $1, $3, $4, $9}'
    
    echo ""
    echo "Kafka JVM Memory Usage:"
    for pid in $KAFKA_PIDS; do
        if [ -f "/proc/$pid/status" ]; then
            echo "  PID $pid:"
            grep -E "VmSize|VmRSS|VmSwap" /proc/$pid/status | awk '{printf "    %-10s %s\n", $1, $2 " " $3}'
        fi
    done
else
    KAFKA_RUNNING="false"
    save_metric "KAFKA_RUNNING" "$KAFKA_RUNNING"
    save_metric "KAFKA_PROCESS_COUNT" "0"
    save_metric "KAFKA_MEMORY_MB" "0"
    
    echo "❌ Kafka is not running"
    echo "Checking for Java processes that might be Kafka:"
    ps aux | grep java | grep -v grep | head -5
fi
print_separator

# Check Kafka connectivity
print_header "KAFKA CONNECTIVITY"
echo "Testing Kafka broker connectivity on localhost:9092..."

# Test with timeout
if timeout 5 bash -c "</dev/tcp/localhost/9092" 2>/dev/null; then
    KAFKA_PORT_ACCESSIBLE="true"
    echo "✅ Kafka port 9092 is accessible"
else
    KAFKA_PORT_ACCESSIBLE="false"
    echo "❌ Cannot connect to Kafka port 9092"
fi

save_metric "KAFKA_PORT_ACCESSIBLE" "$KAFKA_PORT_ACCESSIBLE"

# Count active connections
KAFKA_CONNECTIONS=$(netstat -tna 2>/dev/null | grep -E ":9092|9092:" | wc -l)
save_metric "KAFKA_ACTIVE_CONNECTIONS" "$KAFKA_CONNECTIONS"

echo ""
echo "Network connections on Kafka port:"
netstat -tna 2>/dev/null | grep -E ":9092|9092:" | head -10 | \
awk '{printf "  %-20s %-20s %s\n", $1, $4, $6}' || echo "  No connections found or netstat unavailable"
print_separator

# Broker Information
print_header "KAFKA BROKER INFORMATION"
echo "Attempting to get broker metadata..."

if [ -n "$KAFKA_PIDS" ] && timeout 10 $KAFKA_PATH/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 >/dev/null 2>&1; then
    BROKER_API_RESPONSIVE="true"
    echo "✅ Broker is responding to API calls"
    
    echo ""
    echo "Broker ID and basic info:"
    timeout 10 $KAFKA_PATH/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>/dev/null | head -5
    
    echo ""
    echo "Cluster information:"
    timeout 10 $KAFKA_PATH/bin/kafka-metadata-shell.sh --snapshot /opt/kafka/logs/__cluster_metadata-0/*.log --print cluster 2>/dev/null | head -10 || \
    echo "  Cluster metadata not available (might be in KRaft mode or ZooKeeper mode)"
    
else
    BROKER_API_RESPONSIVE="false"
    echo "❌ Broker is not responding to API calls"
    echo "Possible issues:"
    echo "  - Kafka is not fully started"
    echo "  - Network connectivity issues"
    fi

save_metric "BROKER_API_RESPONSIVE" "$BROKER_API_RESPONSIVE"
print_separator

# Topics List with Partitions
print_header "KAFKA TOPICS OVERVIEW"
echo "Retrieving all topics and their partition information..."

if timeout 15 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    TOPICS=$($KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null)
    TOPIC_COUNT=$(echo "$TOPICS" | wc -l)
    
    # Initialize metrics
    TOTAL_PARTITIONS=0
    TOTAL_REPLICAS=0
    
    save_metric "TOPIC_COUNT" "$TOPIC_COUNT"
    
    echo "✅ Found $TOPIC_COUNT topics:"
    echo ""
    
    if [ -n "$TOPICS" ]; then
        echo "Topic List:"
        echo "$TOPICS" | while read -r topic; do
            if [ -n "$topic" ]; then
                echo "  📝 $topic"
            fi
        done
        
        echo ""
        echo "Detailed Topic Information:"
        echo "=========================="
        
        echo "$TOPICS" | while read -r topic; do
            if [ -n "$topic" ]; then
                echo ""
                echo "Topic: $topic"
                echo "-------------------"
                
                # Get topic details with timeout
                topic_info=$(timeout 10 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$topic" 2>/dev/null)
                
                if [ -n "$topic_info" ]; then
                    # Parse basic info
                    partition_count=$(echo "$topic_info" | grep -E "PartitionCount" | awk '{print $4}')
                    replication_factor=$(echo "$topic_info" | grep -E "ReplicationFactor" | awk '{print $6}')
                    
                    # Accumulate metrics
                    TOTAL_PARTITIONS=$((TOTAL_PARTITIONS + partition_count))
                    TOTAL_REPLICAS=$((TOTAL_REPLICAS + (partition_count * replication_factor)))
                    
                    echo "  Partitions: $partition_count"
                    echo "  Replication Factor: $replication_factor"
                    
                    # Show partition details
                    echo "  Partition Details:"
                    echo "$topic_info" | grep -E "Topic:|Partition:" | \
                    awk '/Partition:/ {printf "    Partition %s: Leader=%s, Replicas=[%s], ISR=[%s]\n", $2, $4, $6, $8}'
                else
                    echo "  ❌ Could not retrieve details for topic: $topic"
                fi
            fi
        done
        
        # Save accumulated metrics
        save_metric "TOTAL_PARTITIONS" "$TOTAL_PARTITIONS"
        save_metric "TOTAL_REPLICAS" "$TOTAL_REPLICAS"
    else
        echo "No topics found"
        save_metric "TOTAL_PARTITIONS" "0"
        save_metric "TOTAL_REPLICAS" "0"
    fi
else
    echo "❌ Cannot retrieve topics list"
    save_metric "TOPIC_COUNT" "0"
    save_metric "TOTAL_PARTITIONS" "0"
    save_metric "TOTAL_REPLICAS" "0"
    echo "Possible issues:"
    echo "  - Kafka broker is not running"
    echo "  - Bootstrap server is not accessible"
    echo "  - Authentication/authorization issues"
fi
print_separator

# Consumer Groups Overview
print_header "CONSUMER GROUPS OVERVIEW"
echo "Checking active consumer groups..."

if timeout 10 $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
    CONSUMER_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list 2>/dev/null)
    GROUP_COUNT=$(echo "$CONSUMER_GROUPS" | grep -v "^$" | wc -l)
    
    echo "✅ Found $GROUP_COUNT consumer groups:"
    
    if [ "$GROUP_COUNT" -gt 0 ]; then
        echo "$CONSUMER_GROUPS" | while read -r group; do
            if [ -n "$group" ]; then
                echo "  👥 $group"
            fi
        done
        
        echo ""
        echo "Consumer Group Details:"
        echo "======================"
        
        echo "$CONSUMER_GROUPS" | while read -r group; do
            if [ -n "$group" ]; then
                echo ""
                echo "Group: $group"
                echo "-------------------"
                
                group_info=$(timeout 10 $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group "$group" 2>/dev/null)
                
                if [ -n "$group_info" ]; then
                    echo "  Status: Active"
                    member_count=$(echo "$group_info" | grep -E "TOPIC|PARTITION" | wc -l)
                    echo "  Active assignments: $member_count"
                    
                    # Show basic assignment info
                    echo "  Topic assignments:"
                    echo "$group_info" | grep -v "GROUP\|^$" | head -5 | \
                    awk '{printf "    %s (partition %s)\n", $1, $2}' 2>/dev/null || echo "    No active assignments"
                else
                    echo "  Status: Inactive or no assignments"
                fi
            fi
        done
    else
        echo "  No active consumer groups found"
    fi
else
    echo "❌ Cannot retrieve consumer groups"
fi
print_separator

# Kafka Logs and Health Check
print_header "KAFKA HEALTH & LOGS"
echo "Checking Kafka log directories and recent activity..."

KAFKA_LOG_DIR="/opt/kafka/logs"
if [ -d "$KAFKA_LOG_DIR" ]; then
    echo "✅ Kafka log directory exists: $KAFKA_LOG_DIR"
    
    echo ""
    echo "Log directory contents:"
    ls -la "$KAFKA_LOG_DIR" | head -10 | awk '{printf "  %s %s %s %s %s\n", $1, $3, $4, $5, $9}'
    
    echo ""
    echo "Recent log activity (last 5 lines from server.log):"
    if [ -f "$KAFKA_LOG_DIR/server.log" ]; then
        tail -5 "$KAFKA_LOG_DIR/server.log" | sed 's/^/  /'
    else
        echo "  server.log not found"
    fi
    
    echo ""
    echo "Checking for errors in recent logs:"
    if [ -f "$KAFKA_LOG_DIR/server.log" ]; then
        error_count=$(tail -100 "$KAFKA_LOG_DIR/server.log" | grep -i -E "error|exception|failed" | wc -l)
        if [ "$error_count" -gt 0 ]; then
            echo "  ⚠️  Found $error_count recent errors/exceptions"
            echo "  Recent errors:"
            tail -100 "$KAFKA_LOG_DIR/server.log" | grep -i -E "error|exception|failed" | tail -3 | sed 's/^/    /'
        else
            echo "  ✅ No recent errors found in server.log"
        fi
    fi
else
    echo "❌ Kafka log directory not found: $KAFKA_LOG_DIR"
fi
print_separator

# Summary
print_header "KAFKA INFRASTRUCTURE SUMMARY"
if [ -n "$KAFKA_PIDS" ]; then
    echo "✅ Kafka Status: RUNNING"
    echo "🔧 Process Count: $(echo "$KAFKA_PIDS" | wc -w)"
else
    echo "❌ Kafka Status: NOT RUNNING"
fi

if timeout 5 bash -c "</dev/tcp/localhost/9092" 2>/dev/null; then
    echo "✅ Connectivity: PORT 9092 ACCESSIBLE"
else
    echo "❌ Connectivity: PORT 9092 NOT ACCESSIBLE"
fi

echo "📊 Topics Count: ${TOPIC_COUNT:-0}"
echo "👥 Consumer Groups: ${GROUP_COUNT:-0}"

echo "==============================================================================="
echo "                 KAFKA INFRASTRUCTURE STATUS COMPLETE"
echo "==============================================================================="
