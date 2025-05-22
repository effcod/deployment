#!/bin/bash

KAFKA_PATH="/opt/kafka"
TOPIC="$1"

echo "======================= KAFKA DETAILED METRICS ======================="

# Topic partition info
echo "Topic Partition Details:"
$KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic $TOPIC

# Producer and consumer metrics
echo "Active Consumer Groups:"
$KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# Check lag for all consumer groups
echo "Consumer Group Lag Details:"
$KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe

# Get Topic Offset Statistics
echo "Topic Offset Statistics:"
$KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic $TOPIC --time -1

# Calculate throughput over 30 seconds
echo "Starting offset count for throughput calculation..."
INITIAL_OFFSETS=$($KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic $TOPIC --time -1)
echo "Initial offsets: $INITIAL_OFFSETS"
echo "Waiting 30 seconds to calculate message throughput..."
sleep 30
FINAL_OFFSETS=$($KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic $TOPIC --time -1)
echo "Final offsets: $FINAL_OFFSETS"

# Extract numbers and calculate throughput (rough calculation)
INITIAL_SUM=$(echo "$INITIAL_OFFSETS" | awk -F ":" '{sum += $3} END {print sum}')
FINAL_SUM=$(echo "$FINAL_OFFSETS" | awk -F ":" '{sum += $3} END {print sum}')
THROUGHPUT=$(( (FINAL_SUM - INITIAL_SUM) * 2 ))
echo "Estimated throughput: $THROUGHPUT messages per minute"

echo "====================================================================="