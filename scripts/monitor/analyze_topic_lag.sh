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

# Get Topic Offset Statistics - using kafka-consumer-groups instead of GetOffsetShell
echo "Topic Offset Statistics:"
GROUP_CMD_OUTPUT=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe | grep $TOPIC)
if [ -n "$GROUP_CMD_OUTPUT" ]; then
  echo "$GROUP_CMD_OUTPUT"
else
  echo "No consumer groups found for topic $TOPIC, using console consumer to check if topic exists"
  # Use console consumer to check if topic has messages
  TOPIC_EXISTS=$($KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list | grep -x "$TOPIC")
  if [ -n "$TOPIC_EXISTS" ]; then
    echo "Topic $TOPIC exists but has no active consumer groups"
    echo "Checking for messages in topic..."
    MESSAGE_COUNT=$($KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 1 2>/dev/null | wc -l)
    if [ "$MESSAGE_COUNT" -gt "0" ]; then
      echo "Topic contains at least one message"
    else
      echo "Topic appears to be empty or inaccessible"
    fi
  else
    echo "Topic $TOPIC does not exist"
  fi
fi

# Calculate throughput over 30 seconds using console consumer
echo "Starting offset count for throughput calculation..."
# Get initial count by attempting to read a small number of messages
INITIAL_COUNT=$($KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 1 2>/dev/null | wc -l)
echo "Initial check: Topic has at least $INITIAL_COUNT messages"

echo "Waiting 30 seconds to calculate message throughput..."
sleep 30

# Check active consumer groups after waiting
NEW_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe | grep $TOPIC)
if [ -n "$NEW_GROUPS" ]; then
  echo "Consumer group activity after 30 seconds:"
  echo "$NEW_GROUPS"
  
  # Try to calculate throughput from consumer group info
  echo "Calculating approximate throughput based on consumer group offsets..."
else
  echo "No consumer group activity detected for topic $TOPIC"
fi

# Try to estimate throughput by reading messages
echo "Attempting to estimate throughput by reading recent messages..."
NEW_COUNT=$($KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 1000 --timeout-ms 5000 2>/dev/null | wc -l)
echo "Read $NEW_COUNT messages in the sample"

# Calculate estimated throughput (very rough)
if [ "$NEW_COUNT" -gt "$INITIAL_COUNT" ]; then
  DIFF=$((NEW_COUNT - INITIAL_COUNT))
  TPM=$((DIFF * 2))  # Messages per minute (30 seconds * 2)
  echo "Estimated throughput: approximately $TPM messages per minute"
else
  echo "No new messages detected in the sampling period"
fi

echo "====================================================================="