#!/bin/bash
# Greenhouse Stack Deployment
# Run ONCE on the server as the greenhouse user after server-setup.sh.
# After this, all updates happen from your Mac via: make deploy

set -e
cd /opt/greenhouse

echo "DEPLOYING GREENHOUSE CONTROL SYSTEM"
echo "===================================="

# Verify user
if [ "$USER" != "greenhouse" ]; then
    echo "ERROR: Run as greenhouse user: sudo su - greenhouse"
    exit 1
fi

# --- Generate .env with secure passwords ---
if [ -f .env ]; then
    echo "Found existing .env - keeping it."
    echo "Delete .env and re-run this script to regenerate passwords."
else
    echo "Generating secure passwords..."
    cat > .env << EOF
# Generated $(date +%Y-%m-%d) - keep this file safe
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_HA_PASSWORD=$(openssl rand -base64 32)
MQTT_USERNAME=greenhouse
MQTT_PASSWORD=$(openssl rand -base64 16)
TZ=Europe/Oslo
EOF
    chmod 600 .env
    echo "Created .env with secure passwords"
fi

source .env

# --- Mosquitto config ---
echo "Configuring MQTT broker..."
mkdir -p config/mosquitto
cat > config/mosquitto/mosquitto.conf << 'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_type warning
connection_messages true
log_timestamp true

listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd

listener 9001
protocol websockets
EOF

# --- MariaDB config (conservative defaults, works on 4GB-32GB RAM) ---
mkdir -p config/mariadb
cat > config/mariadb/my.cnf << 'EOF'
[mysqld]
# Auto-sizes to 75% of available RAM (capped at 8G by MariaDB default)
# Override innodb_buffer_pool_size in docker-compose if needed
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

max_connections = 100
wait_timeout = 28800

character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# Disable binary logging (not needed without replication)
skip-log-bin

# Security
local_infile = 0

[mysql]
default_character_set = utf8mb4

[client]
default_character_set = utf8mb4
EOF

# --- Create HA secrets.yaml if it doesn't exist ---
if [ ! -f config/homeassistant/secrets.yaml ]; then
    echo "Creating Home Assistant secrets template..."
    mkdir -p config/homeassistant
    cat > config/homeassistant/secrets.yaml << EOF
# Update these with your actual values
latitude: 59.2761
longitude: 5.2034
elevation: 10

# Database (auto-generated)
db_url: mysql://homeassistant:${MYSQL_HA_PASSWORD}@greenhouse_mariadb:3306/homeassistant?charset=utf8mb4

# MQTT (auto-generated)
mqtt_username: ${MQTT_USERNAME}
mqtt_password: ${MQTT_PASSWORD}

# Email notifications (update with your settings)
smtp_server: smtp.gmail.com
smtp_sender: greenhouse@yourdomain.com
smtp_username: your-email@gmail.com
smtp_password: your-app-password
admin_email: admin@yourdomain.com
EOF
    echo "Created secrets.yaml - update email settings later"
fi

# --- Pull and start ---
echo ""
echo "Starting services (first run downloads images, may take a few minutes)..."
docker compose pull
docker compose up -d

echo "Waiting for MariaDB..."
until docker exec greenhouse_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; do
    sleep 2
done
echo "MariaDB ready."

echo "Waiting for Home Assistant..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:8123 >/dev/null 2>&1; then
        echo "Home Assistant ready."
        break
    fi
    sleep 3
done

# --- Set up MQTT password ---
echo "Setting up MQTT authentication..."
docker exec greenhouse_mosquitto mosquitto_passwd -c -b /mosquitto/config/passwd "$MQTT_USERNAME" "$MQTT_PASSWORD"
docker restart greenhouse_mosquitto
sleep 3

# --- Backup cron ---
echo "Setting up daily backup at 2 AM..."
(crontab -l 2>/dev/null | grep -v backup.sh; echo "0 2 * * * /opt/greenhouse/scripts/backup.sh >> /opt/greenhouse/logs/backup.log 2>&1") | crontab -

# --- System monitor cron ---
echo "Setting up system monitor (every 5 minutes)..."
(crontab -l 2>/dev/null | grep -v system-monitor.sh; echo "*/5 * * * * /opt/greenhouse/scripts/system-monitor.sh >> /opt/greenhouse/logs/monitor.log 2>&1") | crontab -

# --- Done ---
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================="
echo "GREENHOUSE SYSTEM DEPLOYED"
echo "========================================="
echo ""
echo "Home Assistant:  http://${SERVER_IP}:8123"
echo "ESPHome:         http://${SERVER_IP}:6052"
echo "MQTT Broker:     ${SERVER_IP}:1883"
echo ""
echo "Credentials stored in: /opt/greenhouse/.env"
echo "Backups: daily at 2 AM to /opt/greenhouse/backups/"
echo ""
echo "From your Mac, you can now manage everything with:"
echo "  make deploy       # push config changes"
echo "  make ssh          # connect to server"
echo "  make status       # check services"
echo "  make logs         # view logs"
echo ""
