#!/bin/bash

KAFKA_PATH="/opt/kafka"
TOPIC="$1"

echo "======================= UNCOMMITTED OFFSETS CHECK ======================="

# List all consumer groups
CONSUMER_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list)

echo "Checking for uncommitted consumer offsets for topic $TOPIC..."

if [ -z "$CONSUMER_GROUPS" ]; then
  echo "No consumer groups found."
  echo "This means either:"
  echo "  1. No consumers have connected to this Kafka cluster"
  echo "  2. All consumers are using 'enable.auto.commit=false' and not manually committing offsets"
  echo "  3. Consumers have only just started without processing any messages yet"
  echo "====================================================================="
  exit 0
fi

for GROUP in $CONSUMER_GROUPS; do
  echo "Consumer Group: $GROUP"
  
  # Get consumer group details using described command
  GROUP_INFO=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group "$GROUP" --describe)
  
  # Filter for the topic we're interested in
  TOPIC_INFO=$(echo "$GROUP_INFO" | grep "$TOPIC")
  
  if [ -n "$TOPIC_INFO" ]; then
    # This is a two-step approach to detect uncommitted offsets:
    # 1. Check if there are inconsistencies in the lag reported by the consumer group tool
    # 2. Check if lag is changing over time despite no new messages being produced
    
    # First check - parse current info and look for warning signs
    echo "$TOPIC_INFO" | while read -r line; do
      # Extract information from the consumer group info
      PARTITION=$(echo "$line" | awk '{print $3}')
      CURRENT_OFFSET=$(echo "$line" | awk '{print $4}')
      LOG_END_OFFSET=$(echo "$line" | awk '{print $5}')
      LAG=$(echo "$line" | awk '{print $6}')
      
      # Check for common issue: positive lag but no movement
      echo "  - Partition $PARTITION: Current offset: $CURRENT_OFFSET, End offset: $LOG_END_OFFSET, Lag: $LAG"
      
      # If lag is large, it's a warning sign - only if LAG is a number
      if [[ "$LAG" =~ ^[0-9]+$ ]] && [ "$LAG" -gt 100 ]; then
        echo "    - WARNING: Significant lag detected! This may indicate consumer processing issues or uncommitted offsets."
      fi
      
      # Check for a common issue: inconsistent offset values - but only if both values are valid numbers
      if [[ "$CURRENT_OFFSET" =~ ^[0-9]+$ ]] && [[ "$LOG_END_OFFSET" =~ ^[0-9]+$ ]]; then
        EXPECTED_LAG=$((LOG_END_OFFSET - CURRENT_OFFSET))
        if [[ "$LAG" =~ ^[0-9]+$ ]] && [ "$LAG" != "$EXPECTED_LAG" ]; then
          echo "    - ALERT: Inconsistent offset values detected!"
          echo "      Reported lag: $LAG, but calculated lag: $EXPECTED_LAG"
          echo "      This inconsistency often indicates uncommitted offsets."
        fi
      fi
    done
    
    # Second check - monitor offset movement over time
    echo "  - Monitoring offset movement for 5 seconds to detect uncommitted offsets..."
    FIRST_INFO=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group "$GROUP" --describe | grep "$TOPIC")
    sleep 5
    SECOND_INFO=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group "$GROUP" --describe | grep "$TOPIC")
    
    # Check if offsets changed
    if [ "$FIRST_INFO" = "$SECOND_INFO" ]; then
      echo "  - No offset movement detected in 5 seconds."
      echo "    This could be normal if no new messages are being produced or consumed."
    else
      echo "  - Offsets changed in 5 seconds. This indicates active consumption."
      
      # Try to extract specific values to compare
      FIRST_CURRENT=$(echo "$FIRST_INFO" | awk '{print $4}')
      SECOND_CURRENT=$(echo "$SECOND_INFO" | awk '{print $4}')
      FIRST_LAG=$(echo "$FIRST_INFO" | awk '{print $6}')
      SECOND_LAG=$(echo "$SECOND_INFO" | awk '{print $6}')
      
      # Only perform the comparison if we have valid numeric values
      if [[ "$FIRST_CURRENT" =~ ^[0-9]+$ ]] && [[ "$SECOND_CURRENT" =~ ^[0-9]+$ ]] && 
         [[ "$FIRST_LAG" =~ ^[0-9]+$ ]] && [[ "$SECOND_LAG" =~ ^[0-9]+$ ]]; then
        
        if [ "$FIRST_CURRENT" = "$SECOND_CURRENT" ] && [ "$FIRST_LAG" != "$SECOND_LAG" ]; then
          echo "    - IMPORTANT: Current offset isn't changing but lag is."
          echo "      This strongly indicates the consumer is processing messages but NOT committing offsets."
        fi
      else
        echo "    - Unable to compare numeric values from different measurements."
      fi
    fi
  else
    echo "  - No information for topic $TOPIC in this consumer group"
  fi
done
echo "====================================================================="