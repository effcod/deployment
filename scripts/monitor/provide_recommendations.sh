#!/bin/bash

# Dynamic Pipeline Performance Recommendations Script
# Analyzes collected metrics and provides specific, data-driven recommendations

echo "==============================================================================="
echo "                    DYNAMIC MONITORING ANALYSIS & RECOMMENDATIONS"
echo "==============================================================================="
echo "Report Generated: $(date)"
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

# Function to print status with icon
print_status() {
    local status="$1"
    local message="$2"
    if [ "$status" = "good" ]; then
        echo "✅ $message"
    elif [ "$status" = "warning" ]; then
        echo "⚠️  $message"
    elif [ "$status" = "critical" ]; then
        echo "❌ $message"
    else
        echo "ℹ️  $message"
    fi
}

# Function to load metrics from file
load_metrics() {
    local file="$1"
    if [ -f "$file" ]; then
        while IFS='=' read -r key value; do
            # Skip empty lines and comments
            if [ -n "$key" ] && [[ ! "$key" =~ ^[[:space:]]*# ]]; then
                export "$key"="$value"
            fi
        done < "$file"
    fi
}

# Load all metrics files
METRICS_DIR="/tmp/monitor"
load_metrics "$METRICS_DIR/system_metrics.txt"
load_metrics "$METRICS_DIR/kafka_metrics.txt"
load_metrics "$METRICS_DIR/topic_metrics.txt"
load_metrics "$METRICS_DIR/throughput_metrics.txt"

print_header "SYSTEM HEALTH ANALYSIS"

# CPU Analysis
if [ -n "$CPU_USAGE_PERCENT" ]; then
    CPU_USAGE=${CPU_USAGE_PERCENT%.*}  # Remove decimal part
    if [ "$CPU_USAGE" -lt 70 ]; then
        print_status "good" "CPU Usage: ${CPU_USAGE}% - Healthy"
    elif [ "$CPU_USAGE" -lt 85 ]; then
        print_status "warning" "CPU Usage: ${CPU_USAGE}% - Moderate load"
        echo "   💡 Consider: Monitor for sustained high usage patterns"
    else
        print_status "critical" "CPU Usage: ${CPU_USAGE}% - High load"
        echo "   🚨 Action needed: Scale resources or optimize processes"
    fi
else
    print_status "info" "CPU metrics not available"
fi

# Memory Analysis
if [ -n "$MEMORY_USAGE_PERCENT" ]; then
    if [ "$MEMORY_USAGE_PERCENT" -lt 80 ]; then
        print_status "good" "Memory Usage: ${MEMORY_USAGE_PERCENT}% - Healthy"
    elif [ "$MEMORY_USAGE_PERCENT" -lt 90 ]; then
        print_status "warning" "Memory Usage: ${MEMORY_USAGE_PERCENT}% - Monitor closely"
        echo "   💡 Consider: Adding more RAM or optimizing memory usage"
    else
        print_status "critical" "Memory Usage: ${MEMORY_USAGE_PERCENT}% - Critical"
        echo "   🚨 Action needed: Immediate memory optimization or scaling required"
    fi
fi

# Swap Analysis
if [ -n "$SWAP_USAGE_PERCENT" ] && [ "$SWAP_USAGE_PERCENT" -gt 0 ]; then
    if [ "$SWAP_USAGE_PERCENT" -lt 10 ]; then
        print_status "good" "Swap Usage: ${SWAP_USAGE_PERCENT}% - Normal"
    elif [ "$SWAP_USAGE_PERCENT" -lt 50 ]; then
        print_status "warning" "Swap Usage: ${SWAP_USAGE_PERCENT}% - Monitor memory pressure"
    else
        print_status "critical" "Swap Usage: ${SWAP_USAGE_PERCENT}% - Performance impact likely"
        echo "   🚨 Action needed: Add RAM, swap is slowing down the system"
    fi
fi

# Disk Analysis
if [ -n "$DISK_USAGE_PERCENT" ]; then
    if [ "$DISK_USAGE_PERCENT" -lt 80 ]; then
        print_status "good" "Disk Usage: ${DISK_USAGE_PERCENT}% - Healthy"
    elif [ "$DISK_USAGE_PERCENT" -lt 90 ]; then
        print_status "warning" "Disk Usage: ${DISK_USAGE_PERCENT}% - Plan for cleanup"
        echo "   💡 Consider: Log rotation, data archival, or disk expansion"
    else
        print_status "critical" "Disk Usage: ${DISK_USAGE_PERCENT}% - Critical"
        echo "   🚨 Action needed: Immediate disk cleanup or expansion required"
    fi
fi

# Load Average Analysis
if [ -n "$LOAD_AVERAGE_1MIN" ] && [ -n "$CPU_CORES" ]; then
    LOAD_PER_CORE=$(echo "scale=2; $LOAD_AVERAGE_1MIN / $CPU_CORES" | bc -l 2>/dev/null || echo "0")
    LOAD_THRESHOLD=$(echo "$LOAD_PER_CORE > 1.0" | bc -l 2>/dev/null || echo "0")
    
    if [ "$LOAD_THRESHOLD" -eq 0 ]; then
        print_status "good" "Load Average: ${LOAD_AVERAGE_1MIN} (${LOAD_PER_CORE} per core) - Normal"
    else
        print_status "warning" "Load Average: ${LOAD_AVERAGE_1MIN} (${LOAD_PER_CORE} per core) - High"
        echo "   💡 Consider: System may be overloaded, check processes and CPU usage"
    fi
fi

print_separator

print_header "KAFKA INFRASTRUCTURE ANALYSIS"

# Kafka Service Status
if [ "$KAFKA_RUNNING" = "true" ]; then
    print_status "good" "Kafka Service: Running (${KAFKA_PROCESS_COUNT} processes)"
    
    # Kafka Memory Analysis
    if [ -n "$KAFKA_MEMORY_MB" ] && [ "$KAFKA_MEMORY_MB" -gt 0 ]; then
        if [ "$KAFKA_MEMORY_MB" -lt 1024 ]; then
            print_status "warning" "Kafka Memory: ${KAFKA_MEMORY_MB}MB - May be insufficient for production"
            echo "   💡 Consider: Increasing Kafka heap size for better performance"
        elif [ "$KAFKA_MEMORY_MB" -gt 4096 ]; then
            print_status "good" "Kafka Memory: ${KAFKA_MEMORY_MB}MB - Good allocation"
        else
            print_status "good" "Kafka Memory: ${KAFKA_MEMORY_MB}MB - Adequate"
        fi
    fi
else
    print_status "critical" "Kafka Service: Not running"
    echo "   🚨 Action needed: Start Kafka service immediately"
    echo "   💡 Check: Service configuration, Java installation, disk space"
fi

# Network Connectivity
if [ "$KAFKA_PORT_ACCESSIBLE" = "true" ]; then
    print_status "good" "Network: Port 9092 accessible"
    
    if [ -n "$KAFKA_ACTIVE_CONNECTIONS" ]; then
        if [ "$KAFKA_ACTIVE_CONNECTIONS" -eq 0 ]; then
            print_status "warning" "Network: No active connections - may indicate no clients"
        elif [ "$KAFKA_ACTIVE_CONNECTIONS" -gt 100 ]; then
            print_status "warning" "Network: ${KAFKA_ACTIVE_CONNECTIONS} connections - monitor for connection leaks"
        else
            print_status "good" "Network: ${KAFKA_ACTIVE_CONNECTIONS} active connections"
        fi
    fi
else
    print_status "critical" "Network: Port 9092 not accessible"
    echo "   🚨 Action needed: Check firewall, Kafka configuration, or service status"
fi

# API Responsiveness
if [ "$BROKER_API_RESPONSIVE" = "true" ]; then
    print_status "good" "Kafka API: Responsive"
else
    print_status "critical" "Kafka API: Not responsive"
    echo "   🚨 Action needed: Check Kafka logs, restart if necessary"
fi

# Topics Analysis
if [ -n "$TOPIC_COUNT" ] && [ "$TOPIC_COUNT" -gt 0 ]; then
    print_status "good" "Topics: ${TOPIC_COUNT} topics configured"
    
    if [ -n "$TOTAL_PARTITIONS" ]; then
        AVG_PARTITIONS_PER_TOPIC=$(echo "scale=1; $TOTAL_PARTITIONS / $TOPIC_COUNT" | bc -l 2>/dev/null || echo "0")
        print_status "info" "Partitions: ${TOTAL_PARTITIONS} total (avg ${AVG_PARTITIONS_PER_TOPIC} per topic)"
        
        if [ $(echo "$AVG_PARTITIONS_PER_TOPIC < 1" | bc -l 2>/dev/null || echo 1) -eq 1 ]; then
            print_status "warning" "Partitioning: Low partition count may limit parallelism"
            echo "   💡 Consider: Increasing partitions for better throughput"
        fi
    fi
    
    if [ -n "$TOTAL_REPLICAS" ]; then
        print_status "info" "Replication: ${TOTAL_REPLICAS} total replicas"
    fi
else
    print_status "warning" "Topics: No topics found or unable to retrieve"
    echo "   💡 Consider: Creating topics or checking Kafka connectivity"
fi

print_separator

print_header "PERFORMANCE & THROUGHPUT ANALYSIS"

# Message Throughput Analysis
if [ -n "$MESSAGES_PER_SEC" ] && [ $(echo "$MESSAGES_PER_SEC > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
    MSG_RATE=$(echo "$MESSAGES_PER_SEC" | cut -d'.' -f1)  # Get integer part
    
    if [ "$MSG_RATE" -lt 10 ]; then
        print_status "warning" "Message Rate: ${MESSAGES_PER_SEC} msgs/sec - Low throughput"
        echo "   💡 Consider: Check producer performance, network latency, or data source"
    elif [ "$MSG_RATE" -lt 100 ]; then
        print_status "good" "Message Rate: ${MESSAGES_PER_SEC} msgs/sec - Moderate throughput"
    elif [ "$MSG_RATE" -lt 1000 ]; then
        print_status "good" "Message Rate: ${MESSAGES_PER_SEC} msgs/sec - Good throughput"
    else
        print_status "good" "Message Rate: ${MESSAGES_PER_SEC} msgs/sec - High throughput"
        echo "   💡 Monitor: Consumer lag and system resources under high load"
    fi
else
    print_status "warning" "Message Rate: No messages detected during monitoring"
    echo "   💡 Check: Producer status, topic accessibility, monitoring duration"
fi

# Data Throughput Analysis
if [ -n "$DATA_MB_PER_SEC" ] && [ $(echo "$DATA_MB_PER_SEC > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
    DATA_RATE=$(echo "$DATA_MB_PER_SEC" | cut -d'.' -f1)  # Get integer part
    
    if [ "$DATA_RATE" -lt 1 ]; then
        print_status "info" "Data Rate: ${DATA_MB_PER_SEC} MB/sec - Light data load"
    elif [ "$DATA_RATE" -lt 10 ]; then
        print_status "good" "Data Rate: ${DATA_MB_PER_SEC} MB/sec - Moderate data load"
    elif [ "$DATA_RATE" -lt 100 ]; then
        print_status "good" "Data Rate: ${DATA_MB_PER_SEC} MB/sec - Heavy data load"
    else
        print_status "warning" "Data Rate: ${DATA_MB_PER_SEC} MB/sec - Very heavy data load"
        echo "   💡 Monitor: Disk I/O, network bandwidth, and consumer processing"
    fi
fi

# Message Size Analysis
if [ -n "$AVG_MESSAGE_SIZE" ] && [ "$AVG_MESSAGE_SIZE" -gt 0 ]; then
    if [ "$AVG_MESSAGE_SIZE" -lt 1024 ]; then
        print_status "good" "Message Size: ${AVG_MESSAGE_SIZE} bytes avg - Small messages"
    elif [ "$AVG_MESSAGE_SIZE" -lt 65536 ]; then  # 64KB
        print_status "good" "Message Size: ${AVG_MESSAGE_SIZE} bytes avg - Medium messages"
    elif [ "$AVG_MESSAGE_SIZE" -lt 1048576 ]; then  # 1MB
        print_status "warning" "Message Size: ${AVG_MESSAGE_SIZE} bytes avg - Large messages"
        echo "   💡 Consider: Message compression, batch optimization"
    else
        print_status "warning" "Message Size: ${AVG_MESSAGE_SIZE} bytes avg - Very large messages"
        echo "   💡 Consider: Message splitting, compression, or external storage"
    fi
fi

# Delay Analysis (if available from topic analysis)
if [ -n "$AVG_PRODUCER_DELAY" ] && [ "$AVG_PRODUCER_DELAY" -gt 0 ]; then
    if [ "$AVG_PRODUCER_DELAY" -lt 1 ]; then
        print_status "good" "Producer Delay: ${AVG_PRODUCER_DELAY}s - Excellent"
    elif [ "$AVG_PRODUCER_DELAY" -lt 5 ]; then
        print_status "warning" "Producer Delay: ${AVG_PRODUCER_DELAY}s - Monitor"
        echo "   💡 Consider: Network optimization, producer tuning"
    else
        print_status "critical" "Producer Delay: ${AVG_PRODUCER_DELAY}s - High"
        echo "   🚨 Action needed: Check network, producer config, Kafka performance"
    fi
fi

if [ -n "$AVG_KAFKA_DELAY" ] && [ "$AVG_KAFKA_DELAY" -gt 0 ]; then
    if [ "$AVG_KAFKA_DELAY" -lt 30 ]; then
        print_status "good" "Consumer Delay: ${AVG_KAFKA_DELAY}s - Good"
    elif [ "$AVG_KAFKA_DELAY" -lt 300 ]; then
        print_status "warning" "Consumer Delay: ${AVG_KAFKA_DELAY}s - Monitor lag"
        echo "   💡 Consider: Consumer scaling, processing optimization"
    else
        print_status "critical" "Consumer Delay: ${AVG_KAFKA_DELAY}s - High lag"
        echo "   🚨 Action needed: Scale consumers, optimize processing, check bottlenecks"
    fi
fi

print_separator

print_header "RECOMMENDATIONS SUMMARY"

# Generate overall health score and recommendations
CRITICAL_ISSUES=0
WARNING_ISSUES=0

# Count issues based on metrics
[ "$KAFKA_RUNNING" != "true" ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
[ "$KAFKA_PORT_ACCESSIBLE" != "true" ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
[ "$BROKER_API_RESPONSIVE" != "true" ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))

[ -n "$CPU_USAGE_PERCENT" ] && [ "${CPU_USAGE_PERCENT%.*}" -gt 85 ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
[ -n "$MEMORY_USAGE_PERCENT" ] && [ "$MEMORY_USAGE_PERCENT" -gt 90 ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
[ -n "$DISK_USAGE_PERCENT" ] && [ "$DISK_USAGE_PERCENT" -gt 90 ] && CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))

[ -n "$CPU_USAGE_PERCENT" ] && [ "${CPU_USAGE_PERCENT%.*}" -gt 70 ] && [ "${CPU_USAGE_PERCENT%.*}" -le 85 ] && WARNING_ISSUES=$((WARNING_ISSUES + 1))
[ -n "$MEMORY_USAGE_PERCENT" ] && [ "$MEMORY_USAGE_PERCENT" -gt 80 ] && [ "$MEMORY_USAGE_PERCENT" -le 90 ] && WARNING_ISSUES=$((WARNING_ISSUES + 1))

echo ""
if [ "$CRITICAL_ISSUES" -eq 0 ] && [ "$WARNING_ISSUES" -eq 0 ]; then
    print_status "good" "Overall Health: EXCELLENT - No issues detected"
    echo ""
    echo "🎉 Your Kafka pipeline is running optimally!"
    echo "   • Continue regular monitoring"
    echo "   • Consider implementing alerting for key metrics"
elif [ "$CRITICAL_ISSUES" -eq 0 ]; then
    print_status "warning" "Overall Health: GOOD - ${WARNING_ISSUES} warning(s) detected"
    echo ""
    echo "📋 Next Steps:"
    echo "   • Address warning items when convenient"
    echo "   • Continue monitoring trends"
elif [ "$CRITICAL_ISSUES" -lt 3 ]; then
    print_status "critical" "Overall Health: NEEDS ATTENTION - ${CRITICAL_ISSUES} critical issue(s)"
    echo ""
    echo "🚨 Immediate Actions Required:"
    echo "   • Address critical issues first"
    echo "   • Monitor system closely after fixes"
else
    print_status "critical" "Overall Health: CRITICAL - Multiple issues detected"
    echo ""
    echo "🚨 URGENT: System requires immediate attention"
    echo "   • Address all critical issues immediately"
    echo "   • Consider stopping non-essential services"
    echo "   • Plan for system maintenance window"
fi

echo ""
echo "📊 Monitoring Data Sources:"
echo "   • System metrics: $METRICS_DIR/system_metrics.txt"
echo "   • Kafka metrics: $METRICS_DIR/kafka_metrics.txt"
echo "   • Topic metrics: $METRICS_DIR/topic_metrics.txt"
echo "   • Throughput metrics: $METRICS_DIR/throughput_metrics.txt"

print_separator

print_header "ACTIONABLE INSIGHTS & NEXT STEPS"

echo ""
echo "🔧 Immediate Actions (if any critical issues detected):"
if [ "$CRITICAL_ISSUES" -gt 0 ]; then
    [ "$KAFKA_RUNNING" != "true" ] && echo "   🚨 Start Kafka service"
    [ "$KAFKA_PORT_ACCESSIBLE" != "true" ] && echo "   🚨 Fix Kafka network connectivity"
    [ "$BROKER_API_RESPONSIVE" != "true" ] && echo "   🚨 Restart Kafka broker"
    [ -n "$CPU_USAGE_PERCENT" ] && [ "${CPU_USAGE_PERCENT%.*}" -gt 85 ] && echo "   🚨 Reduce CPU load or scale resources"
    [ -n "$MEMORY_USAGE_PERCENT" ] && [ "$MEMORY_USAGE_PERCENT" -gt 90 ] && echo "   🚨 Free memory or add RAM"
    [ -n "$DISK_USAGE_PERCENT" ] && [ "$DISK_USAGE_PERCENT" -gt 90 ] && echo "   🚨 Clean up disk space"
else
    echo "   ✅ No immediate critical actions required"
fi

echo ""
echo "📈 Optimization Opportunities:"
if [ -n "$MESSAGES_PER_SEC" ] && [ $(echo "$MESSAGES_PER_SEC > 0" | bc -l 2>/dev/null || echo 0) -eq 1 ]; then
    MSG_RATE=$(echo "$MESSAGES_PER_SEC" | cut -d'.' -f1)
    if [ "$MSG_RATE" -lt 10 ]; then
        echo "   💡 Low throughput detected - investigate producer performance"
    elif [ "$MSG_RATE" -gt 1000 ]; then
        echo "   💡 High throughput - monitor consumer lag and scaling"
    fi
fi

if [ -n "$TOTAL_PARTITIONS" ] && [ -n "$TOPIC_COUNT" ] && [ "$TOPIC_COUNT" -gt 0 ]; then
    AVG_PARTITIONS=$(echo "scale=1; $TOTAL_PARTITIONS / $TOPIC_COUNT" | bc -l 2>/dev/null || echo "0")
    if [ $(echo "$AVG_PARTITIONS < 1" | bc -l 2>/dev/null || echo 1) -eq 1 ]; then
        echo "   💡 Consider increasing partition count for better parallelism"
    fi
fi

echo ""
echo "📋 Monitoring Schedule:"
echo "   • Run this analysis daily for production systems"
echo "   • Weekly for development/staging environments"
echo "   • Before and after major changes"
echo "   • Set up automated alerting for critical thresholds"

echo ""
echo "==============================================================================="
echo "          DYNAMIC ANALYSIS COMPLETE - $(date)"
echo "==============================================================================="