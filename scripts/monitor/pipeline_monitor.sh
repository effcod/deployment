#!/bin/bash

# Constants
TOPIC="$1"
DURATION="$2"
KAFKA_PATH="/opt/kafka"
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

echo "======================= PIPELINE PERFORMANCE MONITOR ======================="
echo "Starting monitoring of topic '$TOPIC' for $DURATION seconds"
echo "Current time: $(date)"
echo "========================================================================"

# Function to print timestamp
timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# Function to check system resources without requiring additional packages
check_system_resources() {
  echo "$(timestamp) - SYSTEM RESOURCES:"
  echo "CPU Usage:"
  top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 + $6}' | awk '{print "Total CPU Usage: " $1 "%"}'
  echo "Memory Usage:"
  free -m
  echo "Disk Usage:"
  df -h | grep -vE '^tmpfs|^udev'
  echo "Disk I/O (iostat not installed):"
  cat /proc/diskstats | awk '{if ($3 ~ /sd/) print $3, "reads:", $4, "writes:", $8}'
  echo "Network Stats:"
  cat /proc/net/dev | grep -E 'eth|ens' | awk '{print $1, "RX:", $2, "TX:", $10}'
  echo "----------------------------------------------------------------------"
}

# Function to check Kafka metrics
check_kafka_metrics() {
  echo "$(timestamp) - KAFKA METRICS:"
  echo "Topic Info for '$TOPIC':"
  $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic $TOPIC
  
  echo "Consumer Group Info:"
  $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
  
  echo "Consumer Group Lag (including uncommitted offsets):"
  $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe | grep $TOPIC
  
  echo "Latest Messages (sample):"
  # Get end offset
  END_OFFSET=$($KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic $TOPIC --time -1 | head -n 1 | awk -F ":" '{print $3}')
  # Calculate starting offset (5 messages before end or 0)
  START_OFFSET=$((END_OFFSET - 5))
  if [ $START_OFFSET -lt 0 ]; then
    START_OFFSET=0
  fi
  
  # Get the messages
  $KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --offset $START_OFFSET --partition 0 --max-messages 5 --property print.timestamp=true | while read -r line; do
    # Extract Kafka timestamp and message timestamp if it exists
    KAFKA_TS=$(echo "$line" | awk '{print $1}')
    MESSAGE=$(echo "$line" | cut -d' ' -f2-)
    
    # Try to extract timestamp from JSON message
    MESSAGE_TS=$(echo "$MESSAGE" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$MESSAGE_TS" ]; then
      # Convert ISO timestamp to epoch for comparison
      MESSAGE_EPOCH=$(date -d "$MESSAGE_TS" +%s 2>/dev/null)
      KAFKA_EPOCH=$(date -d "@$KAFKA_TS" +%s 2>/dev/null)
      CURRENT_EPOCH=$(date +%s)
      
      if [ -n "$MESSAGE_EPOCH" ] && [ -n "$KAFKA_EPOCH" ]; then
        # Calculate delays
        PRODUCER_DELAY=$((KAFKA_EPOCH - MESSAGE_EPOCH))
        CONSUMER_DELAY=$((CURRENT_EPOCH - KAFKA_EPOCH))
        TOTAL_DELAY=$((CURRENT_EPOCH - MESSAGE_EPOCH))
        
        echo "Message: $MESSAGE"
        echo "  - Producer->Kafka delay: ${PRODUCER_DELAY}s"
        echo "  - Kafka->Now delay: ${CONSUMER_DELAY}s"
        echo "  - Total delay: ${TOTAL_DELAY}s"
      else
        echo "Message: $MESSAGE"
        echo "  - Unable to parse timestamps for delay calculation"
      fi
    else
      echo "Message: $MESSAGE"
      echo "  - No timestamp found in message"
    fi
  done
  echo "----------------------------------------------------------------------"
}

# Function to check JVM metrics for Kafka
check_kafka_jvm_metrics() {
  echo "$(timestamp) - KAFKA JVM METRICS:"
  KAFKA_PID=$(pgrep -f org.apache.kafka.Kafka)
  if [ -n "$KAFKA_PID" ]; then
    echo "Kafka Process Memory Usage (PID: $KAFKA_PID):"
    ps -o pid,user,%cpu,%mem,vsz,rss,stat,start,time -p $KAFKA_PID
    
    echo "JVM Heap Usage:"
    jcmd $KAFKA_PID GC.heap_info 2>/dev/null || echo "Unable to get heap info"
    
    echo "Thread Count:"
    jcmd $KAFKA_PID Thread.print -l | wc -l 2>/dev/null || echo "Unable to get thread count"
  else
    echo "Kafka process not found"
  fi
  echo "----------------------------------------------------------------------"
}

# Check for uncommitted consumer offsets
check_uncommitted_offsets() {
  echo "$(timestamp) - CHECKING FOR UNCOMMITTED CONSUMER OFFSETS:"
  
  # List all consumer groups
  CONSUMER_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list)
  
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
        else
          echo "  - Partition $PARTITION: Current offset: $CURRENT_OFFSET, End offset: $LOG_END_OFFSET, Lag: $LAG"
        fi
      done
    else
      echo "  - No information for topic $TOPIC in this consumer group"
    fi
  done
  echo "----------------------------------------------------------------------"
}

# Check for memory pressure on broker
check_broker_pressure() {
  echo "$(timestamp) - BROKER RESOURCE PRESSURE:"
  
  # Check if the broker is under memory pressure
  KAFKA_HEAP_USED=$(jcmd $(pgrep -f org.apache.kafka.Kafka) GC.heap_info 2>/dev/null | grep "used" | awk '{print $3}')
  KAFKA_HEAP_CAPACITY=$(jcmd $(pgrep -f org.apache.kafka.Kafka) GC.heap_info 2>/dev/null | grep "capacity" | awk '{print $3}')
  
  if [ -n "$KAFKA_HEAP_USED" ] && [ -n "$KAFKA_HEAP_CAPACITY" ]; then
    HEAP_USAGE_PCT=$((KAFKA_HEAP_USED * 100 / KAFKA_HEAP_CAPACITY))
    echo "  - Kafka Heap Usage: $HEAP_USAGE_PCT% ($KAFKA_HEAP_USED / $KAFKA_HEAP_CAPACITY)"
    
    if [ $HEAP_USAGE_PCT -gt 80 ]; then
      echo "  - WARNING: Kafka is under memory pressure (>80% heap usage)"
      echo "  - High memory pressure can cause broker delays and affect performance"
    fi
  else
    echo "  - Unable to determine Kafka heap usage"
  fi
  
  # Check for high CPU usage which might indicate broker processing delays
  KAFKA_CPU=$(ps -o %cpu= -p $(pgrep -f org.apache.kafka.Kafka))
  if [ -n "$KAFKA_CPU" ]; then
    KAFKA_CPU_INT=${KAFKA_CPU%.*}
    echo "  - Kafka CPU Usage: $KAFKA_CPU%"
    
    if [ $KAFKA_CPU_INT -gt 80 ]; then
      echo "  - WARNING: Kafka is under CPU pressure (>80% CPU usage)"
      echo "  - High CPU pressure can cause message processing delays"
    fi
  else
    echo "  - Unable to determine Kafka CPU usage"
  fi
  
  # Check for potential disk I/O issues
  KAFKA_DATA_DIR=$(grep "log.dirs" /opt/kafka/config/server.properties | cut -d'=' -f2)
  if [ -n "$KAFKA_DATA_DIR" ]; then
    DISK_USAGE=$(df -h "$KAFKA_DATA_DIR" | tail -1)
    DISK_PCT=$(echo "$DISK_USAGE" | awk '{print $5}' | tr -d '%')
    
    echo "  - Kafka Data Directory: $KAFKA_DATA_DIR"
    echo "  - Disk Usage: $DISK_PCT%"
    
    if [ $DISK_PCT -gt 80 ]; then
      echo "  - WARNING: Disk is nearly full (>80% usage)"
      echo "  - Disk space pressure can cause broker to slow down or fail"
    fi
  else
    echo "  - Unable to determine Kafka data directory"
  fi
  echo "----------------------------------------------------------------------"
}

# Run initial checks
check_system_resources
check_kafka_metrics
check_kafka_jvm_metrics
check_uncommitted_offsets
check_broker_pressure

# Monitor for the specified duration
echo "Monitoring performance for $DURATION seconds..."

CURRENT_TIME=$(date +%s)
while [ $CURRENT_TIME -lt $END_TIME ]; do
  sleep 15
  echo ""
  echo "$(timestamp) - PERIODIC CHECK..."
  check_system_resources
  check_kafka_metrics
  check_uncommitted_offsets
  CURRENT_TIME=$(date +%s)
done

echo "========================================================================"
echo "Monitoring completed at $(date)"
echo "========================================================================"