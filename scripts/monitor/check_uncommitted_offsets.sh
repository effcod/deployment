#!/bin/bash

KAFKA_PATH="/opt/kafka"
TOPIC="$1"

echo "======================= UNCOMMITTED OFFSETS CHECK ======================="

# List all consumer groups
CONSUMER_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list)

echo "Checking for uncommitted consumer offsets for topic $TOPIC..."

for GROUP in $CONSUMER_GROUPS; do
  echo "Consumer Group: $GROUP"
  
  # Get the end offset for each partition of the topic
  END_OFFSETS=$($KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic $TOPIC --time -1)
  
  # Get consumer group details
  GROUP_INFO=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group $GROUP --describe)
  
  # Filter for the topic we're interested in
  TOPIC_INFO=$(echo "$GROUP_INFO" | grep $TOPIC)
  
  if [ -n "$TOPIC_INFO" ]; then
    echo "$TOPIC_INFO" | while read -r line; do
      # Extract information from the consumer group info
      PARTITION=$(echo "$line" | awk '{print $3}')
      CURRENT_OFFSET=$(echo "$line" | awk '{print $4}')
      LOG_END_OFFSET=$(echo "$line" | awk '{print $5}')
      LAG=$(echo "$line" | awk '{print $6}')
      
      # Get the end offset from kafka tools (this is the true latest offset)
      ACTUAL_END_OFFSET=$(echo "$END_OFFSETS" | grep "$TOPIC:$PARTITION:" | awk -F ":" '{print $3}')
      
      # If the log end offset from consumer group differs from the actual end offset,
      # it might indicate uncommitted offsets or a stale consumer
      if [ "$LOG_END_OFFSET" != "$ACTUAL_END_OFFSET" ]; then
        ACTUAL_LAG=$((ACTUAL_END_OFFSET - CURRENT_OFFSET))
        echo "  - Partition $PARTITION: Uncommitted/stale offset detected!"
        echo "    - Current offset: $CURRENT_OFFSET"
        echo "    - Reported log end offset: $LOG_END_OFFSET"
        echo "    - Actual log end offset: $ACTUAL_END_OFFSET"
        echo "    - Reported lag: $LAG"
        echo "    - Actual lag: $ACTUAL_LAG"
        echo "    - IMPORTANT: This indicates the consumer is not committing offsets properly"
      else
        echo "  - Partition $PARTITION: Offsets properly committed. Current: $CURRENT_OFFSET, End: $LOG_END_OFFSET, Lag: $LAG"
      fi
    done
  else
    echo "  - No information for topic $TOPIC in this consumer group"
  fi
done
echo "====================================================================="