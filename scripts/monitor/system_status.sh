#!/bin/bash

# System Status Overview Script
# Similar to 'top' command but with comprehensive system information

# Create metrics directory and file for data sharing
mkdir -p /tmp/monitor
METRICS_FILE="/tmp/monitor/system_metrics.txt"
> "$METRICS_FILE"  # Clear the file

echo "==============================================================================="
echo "                     SYSTEM STATUS OVERVIEW"
echo "==============================================================================="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime)"
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

# Function to save metrics
save_metric() {
    echo "$1=$2" >> "$METRICS_FILE"
}

# CPU Status
print_header "CPU STATUS"
echo "CPU Info:"
lscpu | grep -E "Model name|Architecture|CPU\(s\)|Thread|Socket|Core|MHz"

echo ""
echo "Current CPU Usage:"
# Get overall CPU usage and save metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4+$6}')
CPU_IOWAIT=$(top -bn1 | grep "Cpu(s)" | awk '{print $10}' | sed 's/%wa,//')
LOAD_1MIN=$(cat /proc/loadavg | awk '{print $1}')
LOAD_5MIN=$(cat /proc/loadavg | awk '{print $2}')
LOAD_15MIN=$(cat /proc/loadavg | awk '{print $3}')
CPU_CORES=$(nproc)

save_metric "CPU_USAGE_PERCENT" "$CPU_USAGE"
save_metric "CPU_IOWAIT_PERCENT" "$CPU_IOWAIT"
save_metric "LOAD_AVERAGE_1MIN" "$LOAD_1MIN"
save_metric "LOAD_AVERAGE_5MIN" "$LOAD_5MIN"
save_metric "LOAD_AVERAGE_15MIN" "$LOAD_15MIN"
save_metric "CPU_CORES" "$CPU_CORES"

top -bn1 | grep "Cpu(s)" | awk '{printf "  Total CPU Usage: %.1f%% (user: %s, system: %s, idle: %s, iowait: %s)\n", $2+$4+$6, $2, $4, $8, $10}'

echo ""
echo "Top 10 CPU-consuming processes:"
ps aux --sort=-%cpu | head -11 | awk 'NR==1{printf "%-8s %-8s %-6s %-6s %-10s %-s\n", $1, $2, $3, $4, $11, "COMMAND"} NR>1{printf "%-8s %-8s %-6s %-6s %-10s %-s\n", $1, $2, $3, $4, $11, $11}'

echo ""
echo "Load Average:"
cat /proc/loadavg | awk '{printf "  1min: %s, 5min: %s, 15min: %s\n", $1, $2, $3}'
echo "  CPU Cores: $(nproc)"
print_separator

# Memory Status
print_header "MEMORY STATUS"

# Collect memory metrics
MEMORY_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEMORY_FREE_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
MEMORY_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEMORY_USED_KB=$((MEMORY_TOTAL_KB - MEMORY_AVAILABLE_KB))
MEMORY_USAGE_PERCENT=$((MEMORY_USED_KB * 100 / MEMORY_TOTAL_KB))
SWAP_TOTAL_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_FREE_KB=$(grep SwapFree /proc/meminfo | awk '{print $2}')
SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))
if [ "$SWAP_TOTAL_KB" -gt 0 ]; then
    SWAP_USAGE_PERCENT=$((SWAP_USED_KB * 100 / SWAP_TOTAL_KB))
else
    SWAP_USAGE_PERCENT=0
fi

save_metric "MEMORY_TOTAL_MB" "$((MEMORY_TOTAL_KB / 1024))"
save_metric "MEMORY_USED_MB" "$((MEMORY_USED_KB / 1024))"
save_metric "MEMORY_USAGE_PERCENT" "$MEMORY_USAGE_PERCENT"
save_metric "SWAP_TOTAL_MB" "$((SWAP_TOTAL_KB / 1024))"
save_metric "SWAP_USED_MB" "$((SWAP_USED_KB / 1024))"
save_metric "SWAP_USAGE_PERCENT" "$SWAP_USAGE_PERCENT"

echo "Memory Overview:"
free -h | awk 'NR==1{print "  " $0} NR==2{printf "  %-10s Total: %-8s Used: %-8s Free: %-8s Available: %-8s\n", $1, $2, $3, $4, $7}'

echo ""
echo "Detailed Memory Info:"
grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree" /proc/meminfo | \
awk '{printf "  %-15s %s\n", $1, $2 " " $3}'

echo ""
echo "Top 10 Memory-consuming processes:"
ps aux --sort=-%mem | head -11 | awk 'NR==1{printf "%-8s %-8s %-6s %-6s %-8s %-s\n", $1, $2, $3, $4, $6, "COMMAND"} NR>1{printf "%-8s %-8s %-6s %-6s %-8s %-s\n", $1, $2, $3, $4, $6, $11}'
print_separator

# Disk I/O Status
print_header "DISK & I/O STATUS"

# Collect disk usage metrics
DISK_USAGE_PERCENT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_TOTAL_GB=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
DISK_USED_GB=$(df -BG / | tail -1 | awk '{print $3}' | sed 's/G//')
DISK_FREE_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

save_metric "DISK_USAGE_PERCENT" "$DISK_USAGE_PERCENT"
save_metric "DISK_TOTAL_GB" "$DISK_TOTAL_GB"
save_metric "DISK_USED_GB" "$DISK_USED_GB"
save_metric "DISK_FREE_GB" "$DISK_FREE_GB"

# Collect I/O wait from earlier CPU stats
if [ -n "$CPU_IOWAIT" ]; then
    IOWAIT_CLEAN=$(echo "$CPU_IOWAIT" | sed 's/%wa,//' | sed 's/%//')
    save_metric "IO_WAIT_PERCENT" "$IOWAIT_CLEAN"
fi

echo "Disk Usage:"
df -h | grep -vE "^tmpfs|^udev|^Filesystem" | awk '{printf "  %-20s %-8s %-8s %-8s %-6s %s\n", $1, $2, $3, $4, $5, $6}'

echo ""
echo "Disk I/O Statistics:"
if command -v iostat >/dev/null 2>&1; then
    iostat -x 1 1 | tail -n +4 | grep -E "sd[a-z]|nvme" | \
    awk '{printf "  Device: %-10s r/s: %-6s w/s: %-6s rMB/s: %-6s wMB/s: %-6s util: %s%%\n", $1, $4, $5, $6, $7, $10}'
else
    echo "  iostat not available, using /proc/diskstats:"
    awk '/sd[a-z]/ || /nvme/ {printf "  Device: %-10s reads: %-10s writes: %-10s\n", $3, $4, $8}' /proc/diskstats
fi

echo ""
echo "I/O Wait and System Activity:"
top -bn1 | grep "Cpu(s)" | awk '{printf "  I/O Wait: %s\n", $10}'

if [ -f /proc/pressure/io ]; then
    echo "  I/O Pressure:"
    grep -E "avg10|avg60" /proc/pressure/io | awk '{printf "    %s\n", $0}'
fi
print_separator

# Network Status
print_header "NETWORK STATUS"
echo "Network Interfaces:"
cat /proc/net/dev | grep -E "eth|ens|lo|wlan" | \
awk '{gsub(/:/, "", $1); printf "  %-10s RX: %-12s bytes (%-8s packets) TX: %-12s bytes (%-8s packets)\n", $1, $2, $3, $10, $11}'

echo ""
echo "Network Connections:"
netstat_output=$(netstat -tna 2>/dev/null | grep -E "ESTABLISHED|LISTEN" | wc -l)
if [ "$netstat_output" -gt 0 ]; then
    echo "  Established connections: $(netstat -tna 2>/dev/null | grep ESTABLISHED | wc -l)"
    echo "  Listening ports: $(netstat -tna 2>/dev/null | grep LISTEN | wc -l)"
    echo "  Kafka-related connections (port 9092): $(netstat -tna 2>/dev/null | grep -E ":9092|9092:" | wc -l)"
else
    echo "  netstat not available or no connections found"
fi

echo ""
echo "Active Network Sockets:"
ss -tuln 2>/dev/null | head -10 | awk 'NR==1{print "  " $0} NR>1{print "  " $0}' || echo "  ss command not available"
print_separator

# Process Status
print_header "PROCESS STATUS"
echo "Process Overview:"
ps_total=$(ps aux | wc -l)
ps_running=$(ps aux | awk '$8 ~ /R/ {count++} END {print count+0}')
ps_sleeping=$(ps aux | awk '$8 ~ /S/ {count++} END {print count+0}')
ps_zombie=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}')

printf "  Total processes: %s\n" "$ps_total"
printf "  Running: %s, Sleeping: %s, Zombie: %s\n" "$ps_running" "$ps_sleeping" "$ps_zombie"

echo ""
echo "Java/Kafka processes:"
ps aux | grep -E "java|kafka" | grep -v grep | \
awk '{printf "  PID: %-8s User: %-8s CPU: %-6s MEM: %-6s Command: %s\n", $2, $1, $3, $4, $11}'

if [ -z "$(ps aux | grep -E "java|kafka" | grep -v grep)" ]; then
    echo "  No Java/Kafka processes found"
fi
print_separator

# System Resources Summary
print_header "RESOURCE SUMMARY"
# Get key metrics for summary
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4+$6}' | cut -d'%' -f1)
mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
load_avg=$(cat /proc/loadavg | awk '{print $1}')

echo "  CPU Usage: ${cpu_usage}%"
echo "  Memory Usage: ${mem_usage}%"
echo "  Root Disk Usage: ${disk_usage}%"
echo "  Load Average (1min): ${load_avg}"

# Alert on high usage
echo ""
echo "Resource Alerts:"
if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
    echo "  ⚠️  HIGH CPU USAGE: ${cpu_usage}%"
fi
if (( $(echo "$mem_usage > 80" | bc -l 2>/dev/null || echo 0) )); then
    echo "  ⚠️  HIGH MEMORY USAGE: ${mem_usage}%"
fi
if [ "$disk_usage" -gt 80 ]; then
    echo "  ⚠️  HIGH DISK USAGE: ${disk_usage}%"
fi
if (( $(echo "$load_avg > $(nproc)" | bc -l 2>/dev/null || echo 0) )); then
    echo "  ⚠️  HIGH LOAD AVERAGE: ${load_avg} (cores: $(nproc))"
fi

echo "==============================================================================="
echo "                     SYSTEM STATUS OVERVIEW COMPLETE"
echo "==============================================================================="
