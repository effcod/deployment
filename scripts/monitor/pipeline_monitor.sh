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
  $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe | grep $TOPIC || echo "No consumer groups found for this topic"
  
  echo "Latest Messages (sample):"
  # Get end offset using kafka-run-class with the correct class path
  END_OFFSET=$($KAFKA_PATH/bin/kafka-run-class.sh kafka.admin.ConsumerGroupCommand --bootstrap-server localhost:9092 --describe --offsets --topic $TOPIC | grep -v TOPIC | head -n1 | awk '{print $4}')
  
  # If we couldn't get the offset, try an alternative method
  if [ -z "$END_OFFSET" ]; then
    echo "Unable to get end offset using ConsumerGroupCommand, trying alternative method..."
    END_OFFSET=$($KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 1 2>/dev/null | wc -l)
    if [ "$END_OFFSET" -gt "0" ]; then
      echo "Topic contains at least one message"
    else
      echo "Topic appears to be empty or inaccessible"
      return
    fi
  fi
  
  # Calculate starting offset (5 messages before end or 0)
  START_OFFSET=0
  if [ -n "$END_OFFSET" ] && [ "$END_OFFSET" -gt 5 ]; then
    START_OFFSET=$((END_OFFSET - 5))
  fi
  
  echo "Attempting to read messages from the topic..."
  # Get the messages
  $KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 5 --property print.timestamp=true 2>/dev/null | while read -r line; do
    # Extract Kafka timestamp and message timestamp if it exists
    KAFKA_TS=$(echo "$line" | awk '{print $1}')
    MESSAGE=$(echo "$line" | cut -d' ' -f2-)
    
    echo "Message: $MESSAGE"
    
    # Try to extract timestamp from JSON message - look for different patterns
    if echo "$MESSAGE" | grep -q "timestamp"; then
      # Try with double quotes first
      MESSAGE_TS=$(echo "$MESSAGE" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
      
      # If that didn't work, try with different quotes or formats
      if [ -z "$MESSAGE_TS" ]; then
        MESSAGE_TS=$(echo "$MESSAGE" | grep -o "'timestamp':'[^']*'" | cut -d"'" -f4)
      fi
      
      if [ -z "$MESSAGE_TS" ]; then
        MESSAGE_TS=$(echo "$MESSAGE" | grep -o "timestamp[\"': ]*[^\"',}]*" | sed 's/timestamp[\"': ]*//g')
      fi
      
      if [ -n "$MESSAGE_TS" ]; then
        echo "  - Found timestamp in message: $MESSAGE_TS"
        # Convert ISO timestamp to epoch for comparison
        MESSAGE_EPOCH=$(date -d "$MESSAGE_TS" +%s 2>/dev/null)
        KAFKA_EPOCH=$(date -d "@$KAFKA_TS" +%s 2>/dev/null || echo "")
        CURRENT_EPOCH=$(date +%s)
        
        if [ -n "$MESSAGE_EPOCH" ] && [ -n "$KAFKA_EPOCH" ] && [ "$KAFKA_EPOCH" != "" ]; then
          # Calculate delays
          PRODUCER_DELAY=$((KAFKA_EPOCH - MESSAGE_EPOCH))
          CONSUMER_DELAY=$((CURRENT_EPOCH - KAFKA_EPOCH))
          TOTAL_DELAY=$((CURRENT_EPOCH - MESSAGE_EPOCH))
          
          echo "  - Producer->Kafka delay: ${PRODUCER_DELAY}s"
          echo "  - Kafka->Now delay: ${CONSUMER_DELAY}s"
          echo "  - Total delay: ${TOTAL_DELAY}s"
        else
          echo "  - Unable to parse timestamps for delay calculation"
          echo "  - Message timestamp: $MESSAGE_TS"
          echo "  - Kafka timestamp: $KAFKA_TS"
        fi
      else
        echo "  - No timestamp found in message"
      fi
    else
      echo "  - No timestamp field found in message"
    fi
  done
  echo "----------------------------------------------------------------------"
}

# Function to check JVM metrics for Kafka
check_kafka_jvm_metrics() {
  echo "$(timestamp) - KAFKA JVM METRICS:"
  # Look for Kafka process with different possible patterns
  KAFKA_PID=$(ps aux | grep -E 'kafka\.Kafka|kafka\.ServerMain|kafka\.server\.KafkaServer|org\.apache\.kafka\.Kafka' | grep -v grep | awk '{print $2}' | head -1)
  
  if [ -n "$KAFKA_PID" ]; then
    echo "Kafka Process found with PID: $KAFKA_PID"
    echo "Kafka Process Memory Usage:"
    ps -p $KAFKA_PID -o pid,user,%cpu,%mem,vsz,rss,stat,start,time,comm
    
    # Try to get JVM metrics if possible
    if command -v jcmd &> /dev/null; then
      echo "JVM Heap Usage (if available):"
      jcmd $KAFKA_PID GC.heap_info 2>/dev/null || echo "Unable to get heap info"
      
      echo "Thread Count:"
      jcmd $KAFKA_PID Thread.print -l 2>/dev/null | wc -l || echo "Unable to get thread count"
    else
      echo "jcmd not available, using alternative metrics:"
      echo "Memory usage from /proc:"
      cat /proc/$KAFKA_PID/status 2>/dev/null | grep -E 'VmSize|VmRSS|VmSwap' || echo "Unable to read process memory stats"
    fi
  else
    echo "Kafka process not found. Searching for Java processes that might be Kafka:"
    ps aux | grep java | grep -v grep
  fi
  echo "----------------------------------------------------------------------"
}

# Check for uncommitted consumer offsets
check_uncommitted_offsets() {
  echo "$(timestamp) - CHECKING FOR UNCOMMITTED CONSUMER OFFSETS:"
  
  # List all consumer groups
  CONSUMER_GROUPS=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list)
  
  if [ -z "$CONSUMER_GROUPS" ]; then
    echo "No consumer groups found"
    echo "----------------------------------------------------------------------"
    return
  fi
  
  for GROUP in $CONSUMER_GROUPS; do
    echo "Consumer Group: $GROUP"
    
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
        
        echo "  - Partition $PARTITION: Current offset: $CURRENT_OFFSET, End offset: $LOG_END_OFFSET, Lag: $LAG"
        
        # Check if lag is significant
        if [ "$LAG" -gt 100 ]; then
          echo "    - WARNING: Significant lag detected! This may indicate consumer processing issues."
        fi
        
        # Check for a common issue: inconsistent offset values
        EXPECTED_LAG=$((LOG_END_OFFSET - CURRENT_OFFSET))
        if [ "$LAG" != "$EXPECTED_LAG" ]; then
          echo "    - ALERT: Inconsistent offset values detected!"
          echo "      Reported lag: $LAG, but calculated lag: $EXPECTED_LAG"
          echo "      This inconsistency often indicates uncommitted offsets."
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
  
  # Look for Kafka process with different possible patterns
  KAFKA_PID=$(ps aux | grep -E 'kafka\.Kafka|kafka\.ServerMain|kafka\.server\.KafkaServer|org\.apache\.kafka\.Kafka' | grep -v grep | awk '{print $2}' | head -1)
  
  if [ -n "$KAFKA_PID" ]; then
    echo "  - Kafka process found with PID: $KAFKA_PID"
    
    # Get CPU and memory usage from ps
    KAFKA_CPU=$(ps -p $KAFKA_PID -o %cpu= 2>/dev/null || echo "unknown")
    KAFKA_MEM=$(ps -p $KAFKA_PID -o %mem= 2>/dev/null || echo "unknown")
    
    echo "  - Kafka CPU Usage: $KAFKA_CPU%"
    echo "  - Kafka Memory Usage: $KAFKA_MEM% of system memory"
    
    # Check if CPU or memory usage is high
    if [ "$KAFKA_CPU" != "unknown" ]; then
      KAFKA_CPU_INT=${KAFKA_CPU%.*}
      if [ "$KAFKA_CPU_INT" -gt 80 ]; then
        echo "  - WARNING: Kafka is under CPU pressure (>80% CPU usage)"
        echo "  - High CPU pressure can cause message processing delays"
      fi
    fi
    
    if [ "$KAFKA_MEM" != "unknown" ]; then
      KAFKA_MEM_INT=${KAFKA_MEM%.*}
      if [ "$KAFKA_MEM_INT" -gt 80 ]; then
        echo "  - WARNING: Kafka is under memory pressure (>80% memory usage)"
        echo "  - High memory pressure can cause broker delays and affect performance"
      fi
    fi
    
    # Try to get JVM heap usage if possible
    if command -v jcmd &> /dev/null; then
      KAFKA_HEAP_USED=$(jcmd $KAFKA_PID GC.heap_info 2>/dev/null | grep "used" | awk '{print $3}')
      KAFKA_HEAP_CAPACITY=$(jcmd $KAFKA_PID GC.heap_info 2>/dev/null | grep "capacity" | awk '{print $3}')
      
      if [ -n "$KAFKA_HEAP_USED" ] && [ -n "$KAFKA_HEAP_CAPACITY" ]; then
        HEAP_USAGE_PCT=$((KAFKA_HEAP_USED * 100 / KAFKA_HEAP_CAPACITY))
        echo "  - Kafka Heap Usage: $HEAP_USAGE_PCT% ($KAFKA_HEAP_USED / $KAFKA_HEAP_CAPACITY)"
        
        if [ $HEAP_USAGE_PCT -gt 80 ]; then
          echo "  - WARNING: Kafka is under memory pressure (>80% heap usage)"
          echo "  - High memory pressure can cause broker delays and affect performance"
        fi
      fi
    fi
  else
    echo "  - Kafka process not found, cannot check broker pressure directly"
  fi
  
  # Check for potential disk space issues
  # Try to find Kafka data directory from the server properties
  SERVER_PROPERTIES="/opt/kafka/config/server.properties"
  if [ -f "$SERVER_PROPERTIES" ]; then
    KAFKA_DATA_DIR=$(grep "^log.dirs" "$SERVER_PROPERTIES" | cut -d'=' -f2 | tr -d ' ' || echo "")
    
    if [ -n "$KAFKA_DATA_DIR" ] && [ -d "$KAFKA_DATA_DIR" ]; then
      echo "  - Kafka Data Directory: $KAFKA_DATA_DIR"
      DISK_USAGE=$(df -h "$KAFKA_DATA_DIR" 2>/dev/null | tail -1)
      DISK_PCT=$(echo "$DISK_USAGE" | awk '{print $5}' | tr -d '%')
      
      echo "  - Disk Usage: $DISK_PCT%"
      
      if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt 80 ]; then
        echo "  - WARNING: Disk is nearly full (>80% usage)"
        echo "  - Disk space pressure can cause broker to slow down or fail"
      fi
    else
      echo "  - Kafka data directory not found or not accessible: $KAFKA_DATA_DIR"
      echo "  - Checking overall disk usage:"
      df -h / | tail -1
    fi
  else
    echo "  - Kafka server.properties not found at $SERVER_PROPERTIES"
    echo "  - Checking overall disk usage:"
    df -h / | tail -1
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