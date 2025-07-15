#!/bin/bash
# Greenhouse System Monitor Script
# Monitors system health and container status

set -e

LOG_FILE="/opt/greenhouse/logs/system-monitor.log"
ALERT_EMAIL=""  # Will be set from environment if available

# Create log directory if it doesn't exist
mkdir -p /opt/greenhouse/logs

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to send alerts (if email is configured)
send_alert() {
    local priority=$1
    local subject=$2
    local message=$3
    
    log_message "ALERT [$priority]: $subject"
    
    # Send email alert if mail is available and email is configured
    if command -v mail >/dev/null 2>&1 && [ ! -z "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "[$priority] Greenhouse Alert: $subject" "$ALERT_EMAIL"
    fi
    
    # Log to system journal
    logger -t greenhouse-monitor "[$priority] $subject: $message"
}

# Function to check Docker daemon
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        send_alert "CRITICAL" "Docker Daemon Down" "Docker daemon is not running. Attempting to restart..."
        sudo systemctl restart docker
        sleep 10
        if ! docker info >/dev/null 2>&1; then
            send_alert "CRITICAL" "Docker Restart Failed" "Failed to restart Docker daemon. Manual intervention required."
            return 1
        fi
    fi
    log_message "Docker daemon: OK"
}

# Function to check container health
check_containers() {
    local failed_containers=()
    local containers=("greenhouse_mariadb" "greenhouse_homeassistant" "greenhouse_mosquitto" "greenhouse_esphome")
    
    for container in "${containers[@]}"; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            failed_containers+=("$container")
            log_message "CRITICAL: Container $container is not running"
        else
            # Check if container is healthy (if health check is configured)
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            if [ "$health_status" = "unhealthy" ]; then
                failed_containers+=("$container")
                log_message "CRITICAL: Container $container is unhealthy"
            fi
        fi
    done
    
    if [ ${#failed_containers[@]} -gt 0 ]; then
        send_alert "CRITICAL" "Container Issues" "Failed/unhealthy containers: ${failed_containers[*]}"
        log_message "Attempting to restart failed containers..."
        cd /opt/greenhouse && docker-compose up -d "${failed_containers[@]}"
        return 1
    else
        log_message "All containers: Running and healthy"
    fi
}

# Function to check system resources
check_system_resources() {
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | sed 's/,//')
    cpu_usage=${cpu_usage%.*}  # Remove decimal part
    
    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100.0}')
    
    # Disk usage
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    log_message "System Status - CPU: ${cpu_usage}%, Memory: ${mem_usage}%, Disk: ${disk_usage}%, Load: ${load_avg}"
    
    # Check for critical resource usage
    if [ "$cpu_usage" -gt 90 ]; then
        send_alert "CRITICAL" "High CPU Usage" "CPU usage is at ${cpu_usage}% (threshold: 90%)"
    elif [ "$cpu_usage" -gt 80 ]; then
        log_message "WARNING: CPU usage is at ${cpu_usage}% (threshold: 80%)"
    fi
    
    if [ "$mem_usage" -gt 90 ]; then
        send_alert "CRITICAL" "High Memory Usage" "Memory usage is at ${mem_usage}% (threshold: 90%)"
    elif [ "$mem_usage" -gt 80 ]; then
        log_message "WARNING: Memory usage is at ${mem_usage}% (threshold: 80%)"
    fi
    
    if [ "$disk_usage" -gt 95 ]; then
        send_alert "CRITICAL" "Critical Disk Usage" "Disk usage is at ${disk_usage}% (threshold: 95%)"
    elif [ "$disk_usage" -gt 90 ]; then
        log_message "WARNING: Disk usage is at ${disk_usage}% (threshold: 90%)"
    fi
}

# Function to check database connectivity
check_database() {
    if [ -f /opt/greenhouse/.env ]; then
        source /opt/greenhouse/.env
        
        if ! docker exec greenhouse_mariadb mysqladmin ping -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
            send_alert "CRITICAL" "Database Connection Failed" "Cannot connect to MariaDB database. Service may be down."
            return 1
        fi
        
        # Check database size
        local db_size=$(docker exec greenhouse_mariadb mysql -h localhost -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'size' FROM information_schema.tables WHERE table_schema='homeassistant';" 2>/dev/null | tail -n1)
        
        if [ "${db_size%.*}" -gt 1000 ]; then
            log_message "WARNING: Database size is ${db_size}MB - consider cleanup"
        fi
        
        log_message "Database Status - Size: ${db_size}MB, Connection: OK"
    else
        log_message "WARNING: Cannot check database - .env file not found"
    fi
}

# Function to check Home Assistant API
check_homeassistant() {
    local ha_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8123/manifest.json --connect-timeout 10 || echo "000")
    
    if [ "$ha_status" != "200" ]; then
        send_alert "CRITICAL" "Home Assistant API Error" "Home Assistant returned status code: $ha_status"
        return 1
    fi
    
    log_message "Home Assistant Status - Service: OK (200)"
}

# Function to check network connectivity
check_network() {
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        send_alert "CRITICAL" "Network Connectivity Lost" "Cannot reach external networks (8.8.8.8)"
        return 1
    fi
    
    log_message "Network Status - External connectivity: OK"
}

# Function to cleanup old logs
cleanup_logs() {
    # Keep logs for 30 days
    find /opt/greenhouse/logs -name "*.log" -mtime +30 -delete 2>/dev/null || true
    
    # Cleanup Docker logs older than 7 days
    find /var/lib/docker/containers -name "*.log" -mtime +7 -delete 2>/dev/null || true
}

# Function to check disk space specifically for Docker
check_docker_space() {
    local docker_usage=$(du -sh /var/lib/docker 2>/dev/null | cut -f1 || echo "unknown")
    log_message "Docker Storage Usage: $docker_usage"
    
    # Cleanup Docker system if needed
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 85 ]; then
        log_message "Performing Docker system cleanup due to high disk usage"
        docker system prune -f --volumes
    fi
}

# Set alert email from environment if available
if [ -f /opt/greenhouse/.env ]; then
    source /opt/greenhouse/.env
    ALERT_EMAIL="$WATCHTOWER_EMAIL_TO"
fi

# Main monitoring function
main() {
    log_message "Starting comprehensive system monitoring check"
    
    local exit_code=0
    
    # Run all checks
    check_docker || exit_code=1
    check_containers || exit_code=1
    check_system_resources
    check_database || exit_code=1
    check_homeassistant || exit_code=1
    check_network || exit_code=1
    check_docker_space
    cleanup_logs
    
    if [ $exit_code -eq 0 ]; then
        log_message "System monitoring check completed - All systems healthy"
    else
        log_message "System monitoring check completed - Issues detected and addressed"
    fi
    
    return $exit_code
}

# Run main function
main "$@"
