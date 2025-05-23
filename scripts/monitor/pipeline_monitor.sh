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

# Enhanced system resources check with more detailed system stats
check_system_resources() {
  echo "$(timestamp) - SYSTEM RESOURCES:"
  
  echo "=== CPU USAGE ==="
  echo "Overall CPU usage:"
  top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 + $6}' | awk '{print "Total CPU Usage: " $1 "%"}'
  
  echo "Top 5 CPU consuming processes:"
  ps aux --sort=-%cpu | head -6
  
  echo "=== MEMORY USAGE ==="
  echo "Overall memory stats:"
  free -m
  
  echo "Top 5 memory consuming processes:"
  ps aux --sort=-%mem | head -6
  
  echo "Memory details from /proc/meminfo:"
  grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached" /proc/meminfo
  
  echo "=== DISK USAGE ==="
  echo "Disk space usage:"
  df -h | grep -vE "^tmpfs|^udev"
  
  echo "Disk I/O statistics:"
  cat /proc/diskstats | grep -E "sd[a-z]" | awk '{printf "Device %s: reads=%s writes=%s\n", $3, $4, $8}'
  
  # More detailed I/O stats from /proc
  echo "I/O wait time:"
  top -bn1 | grep "Cpu(s)" | awk '{print $10}'
  
  echo "=== NETWORK STATS ==="
  echo "Network interfaces:"
  cat /proc/net/dev | grep -E "eth|ens|lo" | awk '{printf "Interface %s RX bytes=%s TX bytes=%s\n", $1, $2, $10}'
  
  echo "Network connections:"
  netstat -tna | grep -E "9092|ESTABLISHED" | wc -l | awk '{print "Active TCP connections: " $1}'
  
  echo "=== SYSTEM LOAD ==="
  echo "Load average (1, 5, 15 min):"
  cat /proc/loadavg
  
  echo "=== PROCESS STATS ==="
  echo "Total processes:"
  ps aux | wc -l | awk '{print "Total processes: " $1}'
  
  echo "----------------------------------------------------------------------"
}

# Function to check Kafka metrics
check_kafka_metrics() {
  echo "$(timestamp) - KAFKA METRICS:"
  echo "Topic Info for '$TOPIC':"
  $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$TOPIC"
  
  echo "Consumer Group Info:"
  $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
  
  echo "Consumer Group Lag (including uncommitted offsets):"
  $KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --all-groups --describe | grep "$TOPIC" || echo "No consumer groups found for this topic"
  
  echo "Latest Messages (sample):"
  # We'll use a simpler approach that doesn't require ConsumerGroupCommand
  echo "Attempting to read messages from the topic..."
  
  # Get the messages
  $KAFKA_PATH/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" --from-beginning --max-messages 5 --property print.timestamp=true 2>/dev/null | while read -r line; do
    # Extract Kafka timestamp and message timestamp if it exists
    KAFKA_TS=$(echo "$line" | awk '{print $1}')
    MESSAGE=$(echo "$line" | cut -d' ' -f2-)
    
    echo "Message: $MESSAGE"
    
    # Try to extract timestamp from JSON message - with improved parsing for various formats
    if echo "$MESSAGE" | grep -q "timestamp"; then
      # Get everything between "timestamp": and the next comma or closing bracket
      MESSAGE_TS=$(echo "$MESSAGE" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
      
      # If that didn't work, try other formats
      if [ -z "$MESSAGE_TS" ]; then
        MESSAGE_TS=$(echo "$MESSAGE" | grep -o "'timestamp':'[^']*'" | cut -d"'" -f4)
      fi
      
      # Try with more relaxed pattern
      if [ -z "$MESSAGE_TS" ]; then
        MESSAGE_TS=$(echo "$MESSAGE" | grep -o '"timestamp":[^,}]*' | cut -d':' -f2- | tr -d ' "')
      fi
      
      if [ -n "$MESSAGE_TS" ]; then
        echo "  - Found timestamp in message: $MESSAGE_TS"
        
        # Try multiple date formats for parsing
        if [[ "$MESSAGE_TS" == *"T"* && "$MESSAGE_TS" == *"Z"* ]]; then
          # ISO format like 2025-05-22T08:15:29.189985Z
          # Convert to format date can understand
          SIMPLIFIED_TS=$(echo "$MESSAGE_TS" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$//' | sed 's/T/ /')
          MESSAGE_EPOCH=$(date -d "$SIMPLIFIED_TS" +%s 2>/dev/null || echo "")
        else
          # Try generic parsing
          MESSAGE_EPOCH=$(date -d "$MESSAGE_TS" +%s 2>/dev/null || echo "")
        fi
        
        # Extract Kafka timestamp
        KAFKA_EPOCH=""
        if [[ "$KAFKA_TS" == *":"* ]]; then
          # Format like CreateTime:1747901730393 (milliseconds)
          KAFKA_MS=$(echo "$KAFKA_TS" | cut -d':' -f2)
          KAFKA_EPOCH=$((KAFKA_MS / 1000))
        fi
        
        CURRENT_EPOCH=$(date +%s)
        
        if [ -n "$MESSAGE_EPOCH" ] && [ -n "$KAFKA_EPOCH" ]; then
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
        echo "  - No valid timestamp found in message"
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
  # Look for Kafka process with different possible patterns - Fix for SC1079, SC1083
  KAFKA_PID=$(ps aux | grep -E "kafka\.Kafka|kafka\.ServerMain|kafka\.server\.KafkaServer|org\.apache\.kafka\.Kafka" | grep -v grep | awk '{print $2}' | head -1)
  
  if [ -n "$KAFKA_PID" ]; then
    echo "Kafka Process found with PID: $KAFKA_PID"
    echo "Kafka Process Memory Usage:"
    ps -p "$KAFKA_PID" -o pid,user,%cpu,%mem,vsz,rss,stat,start,time,comm
    
    # Try to get JVM metrics if possible
    if command -v jcmd &> /dev/null; then
      echo "JVM Heap Usage (if available):"
      jcmd "$KAFKA_PID" GC.heap_info 2>/dev/null || echo "Unable to get heap info"
      
      echo "Thread Count:"
      jcmd "$KAFKA_PID" Thread.print -l 2>/dev/null | wc -l || echo "Unable to get thread count"
    else
      echo "jcmd not available, using alternative metrics:"
      echo "Memory usage from /proc:"
      cat /proc/"$KAFKA_PID"/status 2>/dev/null | grep -E "VmSize|VmRSS|VmSwap" || echo "Unable to read process memory stats"
      
      # Check for thread count using /proc
      if [ -d "/proc/$KAFKA_PID/task" ]; then
        THREAD_COUNT=$(ls -1 /proc/"$KAFKA_PID"/task | wc -l)
        echo "Thread count from /proc: $THREAD_COUNT"
      fi
    fi
    
    # Check for open files using /proc
    if [ -d "/proc/$KAFKA_PID/fd" ]; then
      FD_COUNT=$(ls -1 /proc/"$KAFKA_PID"/fd | wc -l)
      echo "Open file descriptors: $FD_COUNT"
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
    GROUP_INFO=$($KAFKA_PATH/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group "$GROUP" --describe)
    
    # Filter for the topic we are interested in
    TOPIC_INFO=$(echo "$GROUP_INFO" | grep "$TOPIC")
    
    if [ -n "$TOPIC_INFO" ]; then
      # Process each line of the topic info separately
      echo "$TOPIC_INFO" | while read -r line; do
        # Extract information from the consumer group info
        PARTITION=$(echo "$line" | awk '{print $3}')
        CURRENT_OFFSET=$(echo "$line" | awk '{print $4}')
        LOG_END_OFFSET=$(echo "$line" | awk '{print $5}')
        LAG=$(echo "$line" | awk '{print $6}')
        
        echo "  - Partition $PARTITION: Current offset: $CURRENT_OFFSET, End offset: $LOG_END_OFFSET, Lag: $LAG"
        
        # Check if lag is significant
        if [[ "$LAG" =~ ^[0-9]+$ ]] && [ "$LAG" -gt 100 ]; then
          echo "    - WARNING: Significant lag detected! This may indicate consumer processing issues."
        fi
        
        # Check for a common issue: inconsistent offset values
        if [[ "$CURRENT_OFFSET" =~ ^[0-9]+$ ]] && [[ "$LOG_END_OFFSET" =~ ^[0-9]+$ ]]; then
          EXPECTED_LAG=$((LOG_END_OFFSET - CURRENT_OFFSET))
          if [[ "$LAG" =~ ^[0-9]+$ ]] && [ "$LAG" != "$EXPECTED_LAG" ]; then
            echo "    - ALERT: Inconsistent offset values detected!"
            echo "      Reported lag: $LAG, but calculated lag: $EXPECTED_LAG"
            echo "      This inconsistency often indicates uncommitted offsets."
          fi
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
  KAFKA_PID=$(ps aux | grep -E "kafka\.Kafka|kafka\.ServerMain|kafka\.server\.KafkaServer|org\.apache\.kafka\.Kafka" | grep -v grep | awk '{print $2}' | head -1)
  
  if [ -n "$KAFKA_PID" ]; then
    echo "  - Kafka process found with PID: $KAFKA_PID"
    
    # Get CPU and memory usage from ps
    KAFKA_CPU=$(ps -p "$KAFKA_PID" -o %cpu= 2>/dev/null || echo "unknown")
    KAFKA_MEM=$(ps -p "$KAFKA_PID" -o %mem= 2>/dev/null || echo "unknown")
    
    echo "  - Kafka CPU Usage: $KAFKA_CPU%"
    echo "  - Kafka Memory Usage: $KAFKA_MEM% of system memory"
    
    # Check if CPU or memory usage is high
    if [ "$KAFKA_CPU" != "unknown" ]; then
      KAFKA_CPU_INT=${KAFKA_CPU%.*}
      if [[ "$KAFKA_CPU_INT" =~ ^[0-9]+$ ]] && [ "$KAFKA_CPU_INT" -gt 80 ]; then
        echo "  - WARNING: Kafka is under CPU pressure (>80% CPU usage)"
        echo "  - High CPU pressure can cause message processing delays"
      fi
    fi
    
    if [ "$KAFKA_MEM" != "unknown" ]; then
      KAFKA_MEM_INT=${KAFKA_MEM%.*}
      if [[ "$KAFKA_MEM_INT" =~ ^[0-9]+$ ]] && [ "$KAFKA_MEM_INT" -gt 80 ]; then
        echo "  - WARNING: Kafka is under memory pressure (>80% memory usage)"
        echo "  - High memory pressure can cause broker delays and affect performance"
      fi
    fi
    
    # Try to get JVM heap usage if possible
    if command -v jcmd &> /dev/null; then
      KAFKA_HEAP_USED=$(jcmd "$KAFKA_PID" GC.heap_info 2>/dev/null | grep "used" | awk '{print $3}')
      KAFKA_HEAP_CAPACITY=$(jcmd "$KAFKA_PID" GC.heap_info 2>/dev/null | grep "capacity" | awk '{print $3}')
      
      if [[ "$KAFKA_HEAP_USED" =~ ^[0-9]+$ ]] && [[ "$KAFKA_HEAP_CAPACITY" =~ ^[0-9]+$ ]] && [ "$KAFKA_HEAP_CAPACITY" -gt 0 ]; then
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
      
      if [[ "$DISK_PCT" =~ ^[0-9]+$ ]] && [ "$DISK_PCT" -gt 80 ]; then
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
while [ "$CURRENT_TIME" -lt $END_TIME ]; do
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