#!/bin/bash

# Topic Analysis & Message Inspection Script
# Analyzes specific topic, reads messages, checks timestamps and delays

TOPIC="$1"
KAFKA_PATH="/opt/kafka"

if [ -z "$TOPIC" ]; then
    echo "Usage: $0 <topic-name>"
    exit 1
fi

echo "==============================================================================="
echo "                  TOPIC ANALYSIS & MESSAGE INSPECTION"
echo "==============================================================================="
echo "Topic: $TOPIC"
echo "Timestamp: $(date)"
echo "==============================================================================="

# Create metrics file for data sharing
METRICS_FILE="/tmp/monitor/topic_metrics.txt"
> "$METRICS_FILE"  # Clear the file

# Initialize metrics variables
MESSAGES_ANALYZED=0
AVG_MESSAGE_SIZE=0
AVG_PRODUCER_DELAY=0
AVG_KAFKA_DELAY=0
CONSUMER_GROUP_COUNT=0
TOTAL_CONSUMER_LAG=0
PARTITION_COUNT=0
REPLICATION_FACTOR=0
TOTAL_MESSAGES=0

# Function to print formatted headers
print_header() {
    echo ""
    echo "--- $1 ---"
}

# Function to print separator
print_separator() {
    echo "-------------------------------------------------------------------------------"
}

# Function to parse timestamp from different formats
parse_timestamp() {
    local ts="$1"
    local parsed_epoch=""
    
    # Try ISO format (2025-05-22T08:15:29.189985Z)
    if [[ "$ts" == *"T"* && "$ts" == *"Z"* ]]; then
        # Remove microseconds and Z, replace T with space
        simplified_ts=$(echo "$ts" | sed 's/\.[0-9]*Z$//' | sed 's/T/ /')
        parsed_epoch=$(date -d "$simplified_ts" +%s 2>/dev/null)
    # Try Unix timestamp (seconds)
    elif [[ "$ts" =~ ^[0-9]{10}$ ]]; then
        parsed_epoch="$ts"
    # Try Unix timestamp (milliseconds)
    elif [[ "$ts" =~ ^[0-9]{13}$ ]]; then
        parsed_epoch=$((ts / 1000))
    # Try other date formats
    else
        parsed_epoch=$(date -d "$ts" +%s 2>/dev/null)
    fi
    
    echo "$parsed_epoch"
}

# Check if topic exists
print_header "TOPIC VALIDATION"
echo "Checking if topic '$TOPIC' exists..."

if timeout 10 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -x "$TOPIC" >/dev/null; then
    echo "✅ Topic '$TOPIC' exists"
else
    echo "❌ Topic '$TOPIC' does not exist"
    echo ""
    echo "Available topics:"
    timeout 10 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | sed 's/^/  /' || echo "  Could not retrieve topics list"
    exit 1
fi
print_separator

# Topic Details
print_header "TOPIC DETAILS"
echo "Retrieving detailed information for topic '$TOPIC'..."

TOPIC_INFO=$(timeout 15 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$TOPIC" 2>/dev/null)

if [ -n "$TOPIC_INFO" ]; then
    echo "✅ Topic details retrieved successfully"
    echo ""
    echo "$TOPIC_INFO"
    
    # Parse key details
    PARTITION_COUNT=$(echo "$TOPIC_INFO" | grep -E "PartitionCount" | awk '{print $4}')
    REPLICATION_FACTOR=$(echo "$TOPIC_INFO" | grep -E "ReplicationFactor" | awk '{print $6}')
    
    echo ""
    echo "Summary:"
    echo "  Partitions: $PARTITION_COUNT"
    echo "  Replication Factor: $REPLICATION_FACTOR"
    
    # Check partition health
    echo ""
    echo "Partition Health:"
    unhealthy_partitions=$(echo "$TOPIC_INFO" | grep -E "Partition:" | grep -v "Isr:" | wc -l)
    if [ "$unhealthy_partitions" -eq 0 ]; then
        echo "  ✅ All partitions appear healthy"
    else
        echo "  ⚠️  Potentially unhealthy partitions detected"
    fi
else
    echo "❌ Could not retrieve topic details"
    exit 1
fi
print_separator

# Consumer Group Status for this topic
print_header "CONSUMER GROUP STATUS"
echo "Checking consumer groups for topic '$TOPIC'..."

CONSUMER_GROUPS=$(timeout 10 $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe 2>/dev/null | grep "$TOPIC")

if [ -n "$CONSUMER_GROUPS" ]; then
    echo "✅ Found consumer groups for topic '$TOPIC':"
    echo ""
    echo "Group Status:"
    echo "$CONSUMER_GROUPS" | awk '{printf "  Group: %-20s Partition: %-3s Current Offset: %-10s Log End Offset: %-10s Lag: %s\n", $1, $3, $4, $5, $6}'
    
    # Calculate total lag
    TOTAL_LAG=$(echo "$CONSUMER_GROUPS" | awk '{sum += $6} END {print sum+0}')
    echo ""
    echo "Total Consumer Lag: $TOTAL_LAG messages"
    
    if [ "$TOTAL_LAG" -gt 1000 ]; then
        echo "  ⚠️  High consumer lag detected!"
    elif [ "$TOTAL_LAG" -gt 100 ]; then
        echo "  ⚠️  Moderate consumer lag detected"
    else
        echo "  ✅ Consumer lag is acceptable"
    fi
else
    echo "ℹ️  No active consumer groups found for topic '$TOPIC'"
fi
print_separator

# Message Inspection - Latest Messages
print_header "LATEST MESSAGES INSPECTION"
echo "Reading latest messages from topic '$TOPIC'..."
echo "Analyzing message timestamps and delays..."

CURRENT_EPOCH=$(date +%s)
MESSAGE_COUNT=0
TOTAL_PRODUCER_DELAY=0
TOTAL_KAFKA_DELAY=0
TOTAL_CONSUMER_DELAY=0

echo ""
echo "Message Analysis (last 5 messages):"
echo "======================================"

# Read latest messages with timeout
timeout 15 $KAFKA_PATH/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages 5 \
    --property print.timestamp=true \
    --property print.key=true \
    --property print.headers=true 2>/dev/null | while IFS= read -r line; do
    
    if [ -n "$line" ]; then
        MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
        echo ""
        echo "Message #$MESSAGE_COUNT:"
        echo "Raw: $line"
        
        # Extract Kafka timestamp (format: CreateTime:1747901730393)
        KAFKA_TS=$(echo "$line" | grep -o "CreateTime:[0-9]*" | cut -d':' -f2)
        if [ -n "$KAFKA_TS" ]; then
            KAFKA_EPOCH=$((KAFKA_TS / 1000))  # Convert from milliseconds
            KAFKA_TIME=$(date -d "@$KAFKA_EPOCH" '+%Y-%m-%d %H:%M:%S')
            echo "  Kafka Timestamp: $KAFKA_TIME (epoch: $KAFKA_EPOCH)"
        else
            echo "  Kafka Timestamp: Not found in expected format"
            KAFKA_EPOCH=""
        fi
        
        # Extract message content (after headers)
        MESSAGE_CONTENT=$(echo "$line" | sed 's/^.*CreateTime:[0-9]*[[:space:]]*//')
        echo "  Message Content: $MESSAGE_CONTENT"
        
        # Try to extract timestamp from message content
        MESSAGE_TS=""
        MESSAGE_EPOCH=""
        
        if echo "$MESSAGE_CONTENT" | grep -q '"timestamp"'; then
            # Extract timestamp from JSON
            MESSAGE_TS=$(echo "$MESSAGE_CONTENT" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
            if [ -z "$MESSAGE_TS" ]; then
                MESSAGE_TS=$(echo "$MESSAGE_CONTENT" | grep -o '"timestamp":[^,}]*' | cut -d':' -f2- | tr -d ' "')
            fi
        elif echo "$MESSAGE_CONTENT" | grep -q "'timestamp'"; then
            # Extract timestamp from Python-style dict
            MESSAGE_TS=$(echo "$MESSAGE_CONTENT" | grep -o "'timestamp':'[^']*'" | cut -d"'" -f4)
        fi
        
        if [ -n "$MESSAGE_TS" ]; then
            echo "  Message Timestamp: $MESSAGE_TS"
            MESSAGE_EPOCH=$(parse_timestamp "$MESSAGE_TS")
            
            if [ -n "$MESSAGE_EPOCH" ]; then
                MESSAGE_TIME=$(date -d "@$MESSAGE_EPOCH" '+%Y-%m-%d %H:%M:%S')
                echo "  Parsed Message Time: $MESSAGE_TIME (epoch: $MESSAGE_EPOCH)"
            else
                echo "  Could not parse message timestamp"
            fi
        else
            echo "  Message Timestamp: Not found in message content"
        fi
        
        # Calculate delays
        if [ -n "$MESSAGE_EPOCH" ] && [ -n "$KAFKA_EPOCH" ] && [ "$MESSAGE_EPOCH" -gt 0 ] && [ "$KAFKA_EPOCH" -gt 0 ]; then
            PRODUCER_DELAY=$((KAFKA_EPOCH - MESSAGE_EPOCH))
            CONSUMER_DELAY=$((CURRENT_EPOCH - KAFKA_EPOCH))
            TOTAL_DELAY=$((CURRENT_EPOCH - MESSAGE_EPOCH))
            
            echo "  Delays:"
            echo "    Producer → Kafka: ${PRODUCER_DELAY}s"
            echo "    Kafka → Now: ${CONSUMER_DELAY}s"
            echo "    Total (Producer → Now): ${TOTAL_DELAY}s"
            
            # Add to running totals for averages
            TOTAL_PRODUCER_DELAY=$((TOTAL_PRODUCER_DELAY + PRODUCER_DELAY))
            TOTAL_KAFKA_DELAY=$((TOTAL_KAFKA_DELAY + CONSUMER_DELAY))
            TOTAL_CONSUMER_DELAY=$((TOTAL_CONSUMER_DELAY + TOTAL_DELAY))
            
            # Flag concerning delays
            if [ "$PRODUCER_DELAY" -gt 60 ]; then
                echo "    ⚠️  High producer delay detected!"
            fi
            if [ "$CONSUMER_DELAY" -gt 300 ]; then
                echo "    ⚠️  High Kafka to consumer delay detected!"
            fi
            if [ "$TOTAL_DELAY" -gt 600 ]; then
                echo "    ⚠️  High total delay detected!"
            fi
        else
            echo "  Delays: Cannot calculate (missing or invalid timestamps)"
        fi
        
        echo "  $(printf '%.0s-' {1..60})"
    fi
done

echo ""
print_separator

# Check message frequency and recent activity
print_header "MESSAGE FREQUENCY & ACTIVITY"
echo "Checking recent message activity..."

# Get offset information for each partition
echo "Partition Offset Information:"
for ((i=0; i<PARTITION_COUNT; i++)); do
    # Get latest offset for partition
    LATEST_OFFSET=$(timeout 10 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -1 2>/dev/null | cut -d':' -f3)
    
    # Get earliest offset for partition  
    EARLIEST_OFFSET=$(timeout 10 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -2 2>/dev/null | cut -d':' -f3)
    
    if [ -n "$LATEST_OFFSET" ] && [ -n "$EARLIEST_OFFSET" ]; then
        MESSAGE_COUNT=$((LATEST_OFFSET - EARLIEST_OFFSET))
        echo "  Partition $i: Latest offset: $LATEST_OFFSET, Earliest: $EARLIEST_OFFSET, Messages: $MESSAGE_COUNT"
    else
        echo "  Partition $i: Could not retrieve offset information"
    fi
done

echo ""
echo "Testing message production rate (10 second sample)..."
echo "Sampling messages over 10 seconds to detect activity..."

# Sample current offset
SAMPLE_START_TIME=$(date +%s)
SAMPLE_START_OFFSETS=""

# Collect initial offsets for all partitions
for ((i=0; i<PARTITION_COUNT; i++)); do
    OFFSET=$(timeout 5 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -1 2>/dev/null | cut -d':' -f3)
    SAMPLE_START_OFFSETS="$SAMPLE_START_OFFSETS $OFFSET"
done

echo "Initial offsets: $SAMPLE_START_OFFSETS"
echo "Waiting 10 seconds..."
sleep 10

# Collect final offsets
SAMPLE_END_TIME=$(date +%s)
SAMPLE_END_OFFSETS=""
TOTAL_NEW_MESSAGES=0

for ((i=0; i<PARTITION_COUNT; i++)); do
    OFFSET=$(timeout 5 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -1 2>/dev/null | cut -d':' -f3)
    SAMPLE_END_OFFSETS="$SAMPLE_END_OFFSETS $OFFSET"
    
    # Calculate new messages for this partition
    START_OFFSET=$(echo "$SAMPLE_START_OFFSETS" | awk -v n=$((i+1)) '{print $n}')
    if [ -n "$START_OFFSET" ] && [ -n "$OFFSET" ] && [ "$OFFSET" -gt "$START_OFFSET" ]; then
        NEW_MESSAGES=$((OFFSET - START_OFFSET))
        TOTAL_NEW_MESSAGES=$((TOTAL_NEW_MESSAGES + NEW_MESSAGES))
        echo "  Partition $i: $NEW_MESSAGES new messages"
    fi
done

SAMPLE_DURATION=$((SAMPLE_END_TIME - SAMPLE_START_TIME))
echo ""
echo "Sample Results:"
echo "  Duration: ${SAMPLE_DURATION} seconds"
echo "  New messages: $TOTAL_NEW_MESSAGES"

if [ "$TOTAL_NEW_MESSAGES" -gt 0 ]; then
    MESSAGES_PER_SEC=$(echo "scale=2; $TOTAL_NEW_MESSAGES / $SAMPLE_DURATION" | bc 2>/dev/null || echo "N/A")
    echo "  Rate: $MESSAGES_PER_SEC messages/second"
    echo "  ✅ Topic is actively receiving messages"
else
    echo "  Rate: 0 messages/second"
    echo "  ℹ️  No new messages detected during sampling period"
fi

print_separator

# Store basic topic info in metrics file
echo "topic_exists=true" >> "$METRICS_FILE"
echo "partition_count=$PARTITION_COUNT" >> "$METRICS_FILE"
echo "replication_factor=$REPLICATION_FACTOR" >> "$METRICS_FILE"

# Summary and Analysis
print_header "TOPIC ANALYSIS SUMMARY"
echo "Topic: $TOPIC"
echo "Analysis Time: $(date)"
echo ""
echo "Topic Configuration:"
echo "  ✅ Partitions: $PARTITION_COUNT"
echo "  ✅ Replication Factor: $REPLICATION_FACTOR"

if [ -n "$CONSUMER_GROUPS" ]; then
    echo "  ✅ Consumer Groups: Active"
    echo "  📊 Total Consumer Lag: $TOTAL_LAG messages"
else
    echo "  ℹ️  Consumer Groups: None active"
fi

echo ""
echo "Message Activity:"
if [ "$TOTAL_NEW_MESSAGES" -gt 0 ]; then
    echo "  ✅ Recent Activity: $TOTAL_NEW_MESSAGES messages in last ${SAMPLE_DURATION}s"
    echo "  📈 Current Rate: ${MESSAGES_PER_SEC:-N/A} msg/sec"
else
    echo "  ⚠️  Recent Activity: No new messages detected"
fi

echo ""
echo "Timestamp Analysis:"
if [ "$MESSAGE_COUNT" -gt 0 ]; then
    echo "  ✅ Messages Analyzed: $MESSAGE_COUNT"
    if [ "$TOTAL_PRODUCER_DELAY" -gt 0 ]; then
        AVG_PRODUCER_DELAY=$((TOTAL_PRODUCER_DELAY / MESSAGE_COUNT))
        AVG_KAFKA_DELAY=$((TOTAL_KAFKA_DELAY / MESSAGE_COUNT))
        echo "  📊 Avg Producer Delay: ${AVG_PRODUCER_DELAY}s"
        echo "  📊 Avg Kafka Delay: ${AVG_KAFKA_DELAY}s"
    fi
else
    echo "  ⚠️  No messages available for timestamp analysis"
fi

echo "==============================================================================="
echo "                TOPIC ANALYSIS & MESSAGE INSPECTION COMPLETE"
echo "==============================================================================="

# Save all collected metrics to file
echo "MESSAGES_ANALYZED=$MESSAGES_ANALYZED" >> "$METRICS_FILE"
echo "AVG_MESSAGE_SIZE=$AVG_MESSAGE_SIZE" >> "$METRICS_FILE"
echo "AVG_PRODUCER_DELAY=$AVG_PRODUCER_DELAY" >> "$METRICS_FILE"
echo "AVG_KAFKA_DELAY=$AVG_KAFKA_DELAY" >> "$METRICS_FILE"
echo "CONSUMER_GROUP_COUNT=$CONSUMER_GROUP_COUNT" >> "$METRICS_FILE"
echo "TOTAL_CONSUMER_LAG=$TOTAL_CONSUMER_LAG" >> "$METRICS_FILE"
echo "PARTITION_COUNT=$PARTITION_COUNT" >> "$METRICS_FILE"
echo "REPLICATION_FACTOR=$REPLICATION_FACTOR" >> "$METRICS_FILE"
echo "TOTAL_MESSAGES=$TOTAL_MESSAGES" >> "$METRICS_FILE"

echo ""
echo "📊 Metrics saved to: $METRICS_FILE"
