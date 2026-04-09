#!/bin/bash
# Greenhouse System Monitor
# Checks container health and restarts failed services.
# Runs every 5 minutes via cron.

set -e

CONTAINERS=("greenhouse_mariadb" "greenhouse_homeassistant" "greenhouse_mosquitto" "greenhouse_esphome")
FAILED=()

# Check each container
for c in "${CONTAINERS[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        FAILED+=("$c")
        echo "$(date): CRITICAL - $c is not running"
    fi
done

# Restart failed containers
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "$(date): Restarting failed containers..."
    cd /opt/greenhouse && docker compose up -d
else
    echo "$(date): All containers healthy"
fi

# Log resource usage
MEM=$(free | awk '/Mem/ {printf "%.0f", ($3/$2)*100}')
DISK=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
echo "$(date): Memory: ${MEM}%, Disk: ${DISK}%"

# Warn on high usage
if [ "$DISK" -gt 90 ]; then
    echo "$(date): WARNING - Disk usage at ${DISK}%"
    docker system prune -f >/dev/null 2>&1
fi
