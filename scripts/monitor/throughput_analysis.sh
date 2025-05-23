#!/bin/bash

# Throughput & Traffic Analysis Script
# Calculates throughput and traffic metrics over a specified duration

TOPIC="$1"
DURATION="${2:-60}"
KAFKA_PATH="/opt/kafka"

if [ -z "$TOPIC" ]; then
    echo "Usage: $0 <topic-name> [duration-seconds]"
    exit 1
fi

echo "==============================================================================="
echo "                   THROUGHPUT & TRAFFIC ANALYSIS"
echo "==============================================================================="
echo "Topic: $TOPIC"
echo "Analysis Duration: ${DURATION} seconds"
echo "Start Time: $(date)"
echo "==============================================================================="

# Create/append to metrics file for data sharing
METRICS_FILE="/tmp/monitor/throughput_metrics.txt"
> "$METRICS_FILE"  # Clear the file

# Function to print formatted headers
print_header() {
    echo ""
    echo "--- $1 ---"
}

# Function to print separator
print_separator() {
    echo "-------------------------------------------------------------------------------"
}

# Function to calculate message size in bytes
calculate_message_size() {
    local message="$1"
    echo "$message" | wc -c
}

# Function to format bytes
format_bytes() {
    local bytes="$1"
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    fi
}

# Verify topic exists
print_header "TOPIC VERIFICATION"
echo "Verifying topic '$TOPIC' exists..."

if ! timeout 10 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -x "$TOPIC" >/dev/null; then
    echo "❌ Topic '$TOPIC' does not exist"
    exit 1
fi

# Get topic partition count
PARTITION_COUNT=$(timeout 10 $KAFKA_PATH/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$TOPIC" 2>/dev/null | grep -E "PartitionCount" | awk '{print $4}')

echo "✅ Topic '$TOPIC' verified"
echo "📊 Partitions: $PARTITION_COUNT"
print_separator

# Collect initial metrics
print_header "INITIAL METRICS COLLECTION"
echo "Collecting baseline metrics..."

START_TIME=$(date +%s)
START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Collect initial offsets for each partition
declare -a START_OFFSETS
declare -a END_OFFSETS
TOTAL_START_MESSAGES=0

echo "Initial partition offsets:"
for ((i=0; i<PARTITION_COUNT; i++)); do
    OFFSET=$(timeout 10 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -1 2>/dev/null | cut -d':' -f3)
    
    if [ -n "$OFFSET" ] && [ "$OFFSET" -ge 0 ]; then
        START_OFFSETS[$i]=$OFFSET
        TOTAL_START_MESSAGES=$((TOTAL_START_MESSAGES + OFFSET))
        echo "  Partition $i: $OFFSET"
    else
        START_OFFSETS[$i]=0
        echo "  Partition $i: 0 (could not retrieve or empty)"
    fi
done

echo ""
echo "Total messages at start: $TOTAL_START_MESSAGES"
print_separator

# Message sampling for size analysis
print_header "MESSAGE SIZE ANALYSIS"
echo "Sampling recent messages to analyze sizes..."

SAMPLE_MESSAGE_COUNT=0
TOTAL_SAMPLE_SIZE=0
declare -a MESSAGE_SIZES

echo "Sampling up to 10 recent messages..."

# Read recent messages to analyze size
timeout 15 $KAFKA_PATH/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages 10 \
    --timeout-ms 10000 2>/dev/null | while IFS= read -r line; do
    
    if [ -n "$line" ]; then
        SAMPLE_MESSAGE_COUNT=$((SAMPLE_MESSAGE_COUNT + 1))
        MESSAGE_SIZE=$(echo "$line" | wc -c)
        TOTAL_SAMPLE_SIZE=$((TOTAL_SAMPLE_SIZE + MESSAGE_SIZE))
        MESSAGE_SIZES[$SAMPLE_MESSAGE_COUNT]=$MESSAGE_SIZE
        
        echo "  Message $SAMPLE_MESSAGE_COUNT: $(format_bytes $MESSAGE_SIZE)"
        
        # Show content preview for first few messages
        if [ "$SAMPLE_MESSAGE_COUNT" -le 3 ]; then
            PREVIEW=$(echo "$line" | cut -c1-100)
            echo "    Preview: $PREVIEW..."
        fi
    fi
done

# Calculate average message size (fallback approach since arrays don't persist in subshell)
SAMPLE_MESSAGES=$(timeout 15 $KAFKA_PATH/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$TOPIC" \
    --from-beginning \
    --max-messages 10 \
    --timeout-ms 10000 2>/dev/null)

if [ -n "$SAMPLE_MESSAGES" ]; then
    SAMPLE_COUNT=$(echo "$SAMPLE_MESSAGES" | wc -l)
    TOTAL_BYTES=$(echo "$SAMPLE_MESSAGES" | wc -c)
    
    if [ "$SAMPLE_COUNT" -gt 0 ]; then
        AVG_MESSAGE_SIZE=$((TOTAL_BYTES / SAMPLE_COUNT))
        echo ""
        echo "Sample Analysis Results:"
        echo "  Messages sampled: $SAMPLE_COUNT"
        echo "  Total sample size: $(format_bytes $TOTAL_BYTES)"
        echo "  Average message size: $(format_bytes $AVG_MESSAGE_SIZE)"
    else
        AVG_MESSAGE_SIZE=100  # Default fallback
        echo ""
        echo "⚠️  No messages available for sampling, using default size estimate: $(format_bytes $AVG_MESSAGE_SIZE)"
    fi
else
    AVG_MESSAGE_SIZE=100  # Default fallback
    echo ""
    echo "⚠️  Could not sample messages, using default size estimate: $(format_bytes $AVG_MESSAGE_SIZE)"
fi
print_separator

# Real-time monitoring phase
print_header "REAL-TIME THROUGHPUT MONITORING"
echo "Starting real-time monitoring for $DURATION seconds..."
echo "Monitor started at: $START_TIMESTAMP"

# Progress indicator setup
PROGRESS_INTERVAL=$((DURATION / 10))
if [ "$PROGRESS_INTERVAL" -lt 5 ]; then
    PROGRESS_INTERVAL=5
fi

echo ""
echo "Progress indicators will show every $PROGRESS_INTERVAL seconds..."
echo "$(printf '%.0s=' {1..50})"

# Real-time monitoring loop
ELAPSED=0
while [ "$ELAPSED" -lt "$DURATION" ]; do
    sleep "$PROGRESS_INTERVAL"
    ELAPSED=$((ELAPSED + PROGRESS_INTERVAL))
    
    PROGRESS_PERCENT=$((ELAPSED * 100 / DURATION))
    PROGRESS_BARS=$((PROGRESS_PERCENT / 2))
    
    printf "\r["
    for ((i=0; i<PROGRESS_BARS; i++)); do printf "="; done
    for ((i=PROGRESS_BARS; i<50; i++)); do printf " "; done
    printf "] %d%% (%ds/%ds)" "$PROGRESS_PERCENT" "$ELAPSED" "$DURATION"
    
    # Show intermediate metrics every 20 seconds
    if [ $((ELAPSED % 20)) -eq 0 ] && [ "$ELAPSED" -lt "$DURATION" ]; then
        echo ""
        echo "Intermediate check at ${ELAPSED}s:"
        
        # Quick offset check for activity
        CURRENT_TOTAL=0
        for ((i=0; i<PARTITION_COUNT; i++)); do
            CURRENT_OFFSET=$(timeout 5 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
                --broker-list localhost:9092 \
                --topic "$TOPIC" \
                --partition "$i" \
                --time -1 2>/dev/null | cut -d':' -f3)
            
            if [ -n "$CURRENT_OFFSET" ] && [ "$CURRENT_OFFSET" -ge 0 ]; then
                CURRENT_TOTAL=$((CURRENT_TOTAL + CURRENT_OFFSET))
            fi
        done
        
        INTERMEDIATE_NEW_MESSAGES=$((CURRENT_TOTAL - TOTAL_START_MESSAGES))
        if [ "$INTERMEDIATE_NEW_MESSAGES" -gt 0 ]; then
            INTERMEDIATE_RATE=$(echo "scale=2; $INTERMEDIATE_NEW_MESSAGES / $ELAPSED" | bc 2>/dev/null || echo "N/A")
            echo "  New messages so far: $INTERMEDIATE_NEW_MESSAGES"
            echo "  Current rate: $INTERMEDIATE_RATE msg/sec"
        else
            echo "  No new messages detected yet"
        fi
        echo "$(printf '%.0s=' {1..50})"
    fi
done

echo ""
echo ""
print_separator

# Final metrics collection
print_header "FINAL METRICS COLLECTION"
END_TIME=$(date +%s)
END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ACTUAL_DURATION=$((END_TIME - START_TIME))

echo "Collecting final metrics..."
echo "End time: $END_TIMESTAMP"
echo "Actual monitoring duration: ${ACTUAL_DURATION} seconds"

# Collect final offsets
TOTAL_END_MESSAGES=0
echo ""
echo "Final partition offsets:"

for ((i=0; i<PARTITION_COUNT; i++)); do
    OFFSET=$(timeout 10 $KAFKA_PATH/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic "$TOPIC" \
        --partition "$i" \
        --time -1 2>/dev/null | cut -d':' -f3)
    
    if [ -n "$OFFSET" ] && [ "$OFFSET" -ge 0 ]; then
        END_OFFSETS[$i]=$OFFSET
        TOTAL_END_MESSAGES=$((TOTAL_END_MESSAGES + OFFSET))
        
        # Calculate per-partition growth
        START_OFFSET=${START_OFFSETS[$i]:-0}
        PARTITION_GROWTH=$((OFFSET - START_OFFSET))
        
        echo "  Partition $i: $OFFSET (+$PARTITION_GROWTH)"
    else
        END_OFFSETS[$i]=${START_OFFSETS[$i]:-0}
        echo "  Partition $i: ${START_OFFSETS[$i]:-0} (could not retrieve final offset)"
    fi
done

echo ""
echo "Total messages at end: $TOTAL_END_MESSAGES"
print_separator

# Calculate throughput metrics
print_header "THROUGHPUT CALCULATIONS"
TOTAL_NEW_MESSAGES=$((TOTAL_END_MESSAGES - TOTAL_START_MESSAGES))

echo "Throughput Analysis Results:"
echo "============================"
echo ""
echo "Time Period:"
echo "  Start: $START_TIMESTAMP"
echo "  End: $END_TIMESTAMP" 
echo "  Duration: ${ACTUAL_DURATION} seconds ($(echo "scale=2; $ACTUAL_DURATION / 60" | bc 2>/dev/null || echo "N/A") minutes)"

echo ""
echo "Message Metrics:"
echo "  Messages at start: $TOTAL_START_MESSAGES"
echo "  Messages at end: $TOTAL_END_MESSAGES"
echo "  New messages: $TOTAL_NEW_MESSAGES"

if [ "$TOTAL_NEW_MESSAGES" -gt 0 ] && [ "$ACTUAL_DURATION" -gt 0 ]; then
    # Calculate rates
    MESSAGES_PER_SEC=$(echo "scale=2; $TOTAL_NEW_MESSAGES / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    MESSAGES_PER_MIN=$(echo "scale=2; $TOTAL_NEW_MESSAGES * 60 / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    MESSAGES_PER_HOUR=$(echo "scale=2; $TOTAL_NEW_MESSAGES * 3600 / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    
    echo ""
    echo "Message Throughput:"
    echo "  Rate: $MESSAGES_PER_SEC messages/second"
    echo "  Rate: $MESSAGES_PER_MIN messages/minute"
    echo "  Rate: $MESSAGES_PER_HOUR messages/hour"
    
    # Calculate data throughput
    TOTAL_BYTES=$((TOTAL_NEW_MESSAGES * AVG_MESSAGE_SIZE))
    BYTES_PER_SEC=$(echo "scale=0; $TOTAL_BYTES / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    KILOBYTES_PER_SEC=$(echo "scale=2; $BYTES_PER_SEC / 1024" | bc 2>/dev/null || echo "0")
    MEGABYTES_PER_SEC=$(echo "scale=3; $BYTES_PER_SEC / 1048576" | bc 2>/dev/null || echo "0")
    
    echo ""
    echo "Data Throughput (estimated):"
    echo "  Total data: $(format_bytes $TOTAL_BYTES)"
    echo "  Rate: $(format_bytes $BYTES_PER_SEC)/second"
    echo "  Rate: ${KILOBYTES_PER_SEC} KB/second"
    echo "  Rate: ${MEGABYTES_PER_SEC} MB/second"
    
    # Performance categories
    echo ""
    echo "Performance Assessment:"
    if [ "$(echo "$MESSAGES_PER_SEC > 1000" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  🚀 HIGH throughput detected (>1000 msg/sec)"
    elif [ "$(echo "$MESSAGES_PER_SEC > 100" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  ✅ GOOD throughput detected (>100 msg/sec)"
    elif [ "$(echo "$MESSAGES_PER_SEC > 10" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  📊 MODERATE throughput detected (>10 msg/sec)"
    elif [ "$(echo "$MESSAGES_PER_SEC > 0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  🐌 LOW throughput detected (<10 msg/sec)"
    else
        echo "  ⚠️  NO throughput detected"
    fi
    
else
    echo ""
    echo "❌ No new messages detected during monitoring period"
    echo "Possible reasons:"
    echo "  - Topic is not actively receiving messages"
    echo "  - Producer is offline or experiencing issues"
    echo "  - Monitoring duration was too short"
    echo "  - Network or connectivity issues"
fi

# Save throughput metrics to file
echo "Throughput Analysis Results" > "$METRICS_FILE"
echo "============================" >> "$METRICS_FILE"
echo "" >> "$METRICS_FILE"
echo "Time Period:" >> "$METRICS_FILE"
echo "  Start: $START_TIMESTAMP" >> "$METRICS_FILE"
echo "  End: $END_TIMESTAMP" >> "$METRICS_FILE"
echo "  Duration: ${ACTUAL_DURATION} seconds ($(echo "scale=2; $ACTUAL_DURATION / 60" | bc 2>/dev/null || echo "N/A") minutes)" >> "$METRICS_FILE"
echo "" >> "$METRICS_FILE"
echo "Message Metrics:" >> "$METRICS_FILE"
echo "  Messages at start: $TOTAL_START_MESSAGES" >> "$METRICS_FILE"
echo "  Messages at end: $TOTAL_END_MESSAGES" >> "$METRICS_FILE"
echo "  New messages: $TOTAL_NEW_MESSAGES" >> "$METRICS_FILE"
echo "" >> "$METRICS_FILE"

if [ "$TOTAL_NEW_MESSAGES" -gt 0 ] && [ "$ACTUAL_DURATION" -gt 0 ]; then
    # Calculate rates
    MESSAGES_PER_SEC=$(echo "scale=2; $TOTAL_NEW_MESSAGES / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    MESSAGES_PER_MIN=$(echo "scale=2; $TOTAL_NEW_MESSAGES * 60 / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    MESSAGES_PER_HOUR=$(echo "scale=2; $TOTAL_NEW_MESSAGES * 3600 / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    
    echo "Message Throughput:" >> "$METRICS_FILE"
    echo "  Rate: $MESSAGES_PER_SEC messages/second" >> "$METRICS_FILE"
    echo "  Rate: $MESSAGES_PER_MIN messages/minute" >> "$METRICS_FILE"
    echo "  Rate: $MESSAGES_PER_HOUR messages/hour" >> "$METRICS_FILE"
    
    # Calculate data throughput
    TOTAL_BYTES=$((TOTAL_NEW_MESSAGES * AVG_MESSAGE_SIZE))
    BYTES_PER_SEC=$(echo "scale=0; $TOTAL_BYTES / $ACTUAL_DURATION" | bc 2>/dev/null || echo "0")
    KILOBYTES_PER_SEC=$(echo "scale=2; $BYTES_PER_SEC / 1024" | bc 2>/dev/null || echo "0")
    MEGABYTES_PER_SEC=$(echo "scale=3; $BYTES_PER_SEC / 1048576" | bc 2>/dev/null || echo "0")
    
    echo "Data Throughput (estimated):" >> "$METRICS_FILE"
    echo "  Total data: $(format_bytes $TOTAL_BYTES)" >> "$METRICS_FILE"
    echo "  Rate: $(format_bytes $BYTES_PER_SEC)/second" >> "$METRICS_FILE"
    echo "  Rate: ${KILOBYTES_PER_SEC} KB/second" >> "$METRICS_FILE"
    echo "  Rate: ${MEGABYTES_PER_SEC} MB/second" >> "$METRICS_FILE"
    echo "" >> "$METRICS_FILE"
    
    # Performance categories
    echo "Performance Assessment:" >> "$METRICS_FILE"
    if [ "$(echo "$MESSAGES_PER_SEC > 1000" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  🚀 HIGH throughput detected (>1000 msg/sec)" >> "$METRICS_FILE"
    elif [ "$(echo "$MESSAGES_PER_SEC > 100" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  ✅ GOOD throughput detected (>100 msg/sec)" >> "$METRICS_FILE"
    elif [ "$(echo "$MESSAGES_PER_SEC > 10" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  📊 MODERATE throughput detected (>10 msg/sec)" >> "$METRICS_FILE"
    elif [ "$(echo "$MESSAGES_PER_SEC > 0" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        echo "  🐌 LOW throughput detected (<10 msg/sec)" >> "$METRICS_FILE"
    else
        echo "  ⚠️  NO throughput detected" >> "$METRICS_FILE"
    fi
    
else
    echo "❌ No new messages detected during monitoring period" >> "$METRICS_FILE"
    echo "Possible reasons:" >> "$METRICS_FILE"
    echo "  - Topic is not actively receiving messages" >> "$METRICS_FILE"
    echo "  - Producer is offline or experiencing issues" >> "$METRICS_FILE"
    echo "  - Monitoring duration was too short" >> "$METRICS_FILE"
    echo "  - Network or connectivity issues" >> "$METRICS_FILE"
fi

# Store throughput metrics for recommendations
echo "messages_per_sec=${MESSAGES_PER_SEC:-0}" >> "$METRICS_FILE"
echo "megabytes_per_sec=${MEGABYTES_PER_SEC:-0}" >> "$METRICS_FILE"
echo "total_new_messages=${TOTAL_NEW_MESSAGES:-0}" >> "$METRICS_FILE"
echo "total_bytes=${TOTAL_BYTES:-0}" >> "$METRICS_FILE"
echo "monitoring_duration=${ACTUAL_DURATION:-0}" >> "$METRICS_FILE"
echo "partition_count=${PARTITION_COUNT:-0}" >> "$METRICS_FILE"

# Calculate partition utilization
if [ "$PARTITION_COUNT" -gt 1 ] && [ "$TOTAL_NEW_MESSAGES" -gt 0 ]; then
    AVG_MESSAGES_PER_PARTITION=$((TOTAL_NEW_MESSAGES / PARTITION_COUNT))
    echo "avg_messages_per_partition=$AVG_MESSAGES_PER_PARTITION" >> "$METRICS_FILE"
    
    # Calculate partition imbalance
    MIN_ACTIVITY=$TOTAL_NEW_MESSAGES
    MAX_ACTIVITY=0
    
    for ((i=0; i<PARTITION_COUNT; i++)); do
        START_OFFSET=${START_OFFSETS[$i]:-0}
        END_OFFSET=${END_OFFSETS[$i]:-0}
        PARTITION_GROWTH=$((END_OFFSET - START_OFFSET))
        
        if [ "$PARTITION_GROWTH" -lt "$MIN_ACTIVITY" ]; then
            MIN_ACTIVITY=$PARTITION_GROWTH
        fi
        if [ "$PARTITION_GROWTH" -gt "$MAX_ACTIVITY" ]; then
            MAX_ACTIVITY=$PARTITION_GROWTH
        fi
    done
    
    if [ "$MAX_ACTIVITY" -gt 0 ]; then
        IMBALANCE_RATIO=$(echo "scale=2; $MAX_ACTIVITY / ($MIN_ACTIVITY + 1)" | bc 2>/dev/null || echo "1")
        echo "partition_imbalance_ratio=$IMBALANCE_RATIO" >> "$METRICS_FILE"
    else
        echo "partition_imbalance_ratio=1" >> "$METRICS_FILE"
    fi
else
    echo "avg_messages_per_partition=0" >> "$METRICS_FILE"
    echo "partition_imbalance_ratio=1" >> "$METRICS_FILE"
fi

print_separator

# Partition distribution analysis
print_header "PARTITION DISTRIBUTION ANALYSIS"
echo "Analyzing message distribution across partitions..."

echo ""
echo "Per-Partition Activity:"
for ((i=0; i<PARTITION_COUNT; i++)); do
    START_OFFSET=${START_OFFSETS[$i]:-0}
    END_OFFSET=${END_OFFSETS[$i]:-0}
    PARTITION_GROWTH=$((END_OFFSET - START_OFFSET))
    
    if [ "$TOTAL_NEW_MESSAGES" -gt 0 ]; then
        PARTITION_PERCENT=$(echo "scale=1; $PARTITION_GROWTH * 100 / $TOTAL_NEW_MESSAGES" | bc 2>/dev/null || echo "0")
    else
        PARTITION_PERCENT="0"
    fi
    
    echo "  Partition $i: $PARTITION_GROWTH messages (${PARTITION_PERCENT}%)"
done

# Check for partition imbalance
if [ "$TOTAL_NEW_MESSAGES" -gt 0 ] && [ "$PARTITION_COUNT" -gt 1 ]; then
    EXPECTED_PER_PARTITION=$((TOTAL_NEW_MESSAGES / PARTITION_COUNT))
    echo ""
    echo "Distribution Analysis:"
    echo "  Expected per partition (even distribution): $EXPECTED_PER_PARTITION messages"
    
    # Find min and max partition activity
    MIN_ACTIVITY=$TOTAL_NEW_MESSAGES
    MAX_ACTIVITY=0
    
    for ((i=0; i<PARTITION_COUNT; i++)); do
        START_OFFSET=${START_OFFSETS[$i]:-0}
        END_OFFSET=${END_OFFSETS[$i]:-0}
        PARTITION_GROWTH=$((END_OFFSET - START_OFFSET))
        
        if [ "$PARTITION_GROWTH" -lt "$MIN_ACTIVITY" ]; then
            MIN_ACTIVITY=$PARTITION_GROWTH
        fi
        if [ "$PARTITION_GROWTH" -gt "$MAX_ACTIVITY" ]; then
            MAX_ACTIVITY=$PARTITION_GROWTH
        fi
    done
    
    if [ "$MAX_ACTIVITY" -gt 0 ]; then
        IMBALANCE_RATIO=$(echo "scale=2; $MAX_ACTIVITY / ($MIN_ACTIVITY + 1)" | bc 2>/dev/null || echo "1")
        echo "  Min partition activity: $MIN_ACTIVITY messages"
        echo "  Max partition activity: $MAX_ACTIVITY messages"
        echo "  Imbalance ratio: $IMBALANCE_RATIO"
        
        if [ "$(echo "$IMBALANCE_RATIO > 3" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
            echo "  ⚠️  Significant partition imbalance detected!"
        elif [ "$(echo "$IMBALANCE_RATIO > 2" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
            echo "  ⚠️  Moderate partition imbalance detected"
        else
            echo "  ✅ Partition distribution appears balanced"
        fi
    fi
fi

print_separator

# Summary and recommendations
print_header "THROUGHPUT ANALYSIS SUMMARY"
echo "Summary for topic '$TOPIC':"
echo "Analysis period: ${ACTUAL_DURATION} seconds"
echo "$(date)"

echo ""
echo "Key Metrics:"
if [ "$TOTAL_NEW_MESSAGES" -gt 0 ]; then
    echo "  ✅ Active: $TOTAL_NEW_MESSAGES new messages"
    echo "  📊 Rate: ${MESSAGES_PER_SEC:-0} msg/sec, ${MEGABYTES_PER_SEC:-0} MB/sec"
    echo "  💾 Volume: $(format_bytes ${TOTAL_BYTES:-0}) total"
    echo "  🔀 Partitions: $PARTITION_COUNT (distribution: balanced/imbalanced)"
else
    echo "  ❌ Inactive: No new messages detected"
    echo "  📊 Rate: 0 msg/sec, 0 MB/sec"
    echo "  🔀 Partitions: $PARTITION_COUNT"
fi

echo ""
echo "Recommendations:"
if [ "$TOTAL_NEW_MESSAGES" -eq 0 ]; then
    echo "  • Check producer status and connectivity"
    echo "  • Verify topic configuration and accessibility"
    echo "  • Consider longer monitoring duration"
elif [ "$(echo "${MESSAGES_PER_SEC:-0} < 1" | bc -l 2>/dev/null || echo 1)" -eq 1 ]; then
    echo "  • Monitor for longer periods to get better baseline"
    echo "  • Consider if low throughput is expected for this topic"
elif [ "$(echo "${MESSAGES_PER_SEC:-0} > 1000" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
    echo "  • Excellent throughput - monitor consumer lag"
    echo "  • Consider adding consumer instances if lag develops"
    echo "  • Monitor system resources under high load"
else
    echo "  • Throughput appears normal for typical workloads"
    echo "  • Continue monitoring for trends and patterns"
fi

echo "==============================================================================="
echo "                  THROUGHPUT & TRAFFIC ANALYSIS COMPLETE"
echo "==============================================================================="

# Save all collected metrics to file
echo "TOTAL_NEW_MESSAGES=${TOTAL_NEW_MESSAGES:-0}" >> "$METRICS_FILE"
echo "MESSAGES_PER_SEC=${MESSAGES_PER_SEC:-0}" >> "$METRICS_FILE"
echo "TOTAL_DATA_BYTES=${TOTAL_DATA_BYTES:-0}" >> "$METRICS_FILE"
echo "DATA_MB_PER_SEC=${DATA_MB_PER_SEC:-0}" >> "$METRICS_FILE"
echo "AVG_MESSAGE_SIZE=${AVG_MESSAGE_SIZE:-0}" >> "$METRICS_FILE"
echo "MIN_MESSAGE_SIZE=${MIN_MESSAGE_SIZE:-0}" >> "$METRICS_FILE"
echo "MAX_MESSAGE_SIZE=${MAX_MESSAGE_SIZE:-0}" >> "$METRICS_FILE"
echo "PARTITION_COUNT=${PARTITION_COUNT:-0}" >> "$METRICS_FILE"
echo "MONITORING_DURATION=${MONITORING_DURATION:-0}" >> "$METRICS_FILE"

echo ""
echo "📊 Throughput metrics saved to: $METRICS_FILE"
