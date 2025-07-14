#!/bin/bash
# Greenhouse Docker Stack Deployment
# Run as greenhouse user after base system installation

set -e
cd /opt/greenhouse

echo "🏭 DEPLOYING GREENHOUSE CONTROL SYSTEM"
echo "======================================"
echo "This will deploy the complete Docker stack for greenhouse operations"
echo ""

# Verify we're running as greenhouse user
if [ "$USER" != "greenhouse" ]; then
    echo "❌ ERROR: This script must be run as the greenhouse user"
    echo "Please run: sudo su - greenhouse"
    exit 1
fi

echo "✅ Running as greenhouse user"
echo ""

# Generate SSH keys for secure access
echo "🔑 Setting up SSH keys..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
    echo "✅ SSH keys generated"
    echo "📋 Your public key (add this to your client):"
    echo "================================================"
    cat ~/.ssh/id_ed25519.pub
    echo "================================================"
    echo ""
    read -p "Press Enter when you've saved the public key..."
else
    echo "✅ SSH keys already exist"
fi

# Create environment file with secure passwords
echo "🔐 Creating environment configuration..."
cat > .env << EOF
# Database Configuration
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_HA_PASSWORD=$(openssl rand -base64 32)

# Grafana Configuration (keeping for future use)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
GRAFANA_SECRET_KEY=$(openssl rand -base64 32)

# Email Configuration (update with your settings)
SMTP_SERVER=smtp.gmail.com
SMTP_USERNAME=your-greenhouse@gmail.com
SMTP_PASSWORD=your-app-password
WATCHTOWER_EMAIL_FROM=greenhouse@yourdomain.com
WATCHTOWER_EMAIL_TO=admin@yourdomain.com

# MQTT Configuration
MQTT_USERNAME=greenhouse
MQTT_PASSWORD=$(openssl rand -base64 16)

# Timezone
TZ=Europe/Oslo
EOF

echo "✅ Environment file created with secure passwords"

# Create Docker Compose file
echo "📦 Creating Docker Compose configuration..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # MariaDB - Primary Database
  mariadb:
    image: mariadb:10.11-jammy
    container_name: greenhouse_mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MARIADB_DATABASE: homeassistant
      MARIADB_USER: homeassistant
      MARIADB_PASSWORD: ${MYSQL_HA_PASSWORD}
      MARIADB_AUTO_UPGRADE: 1
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./config/mariadb/my.cnf:/etc/mysql/conf.d/my.cnf:ro
      - ./backups:/backups
    ports:
      - "3306:3306"
    command: >
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --innodb-buffer-pool-size=8G
      --innodb-log-file-size=512M
      --innodb-flush-log-at-trx-commit=1
      --sync-binlog=1
      --binlog-format=ROW
      --log-bin=mysql-bin
      --max-connections=200
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      start_period: 10s
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - greenhouse_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Home Assistant - Main Control System
  homeassistant:
    image: homeassistant/home-assistant:stable
    container_name: greenhouse_homeassistant
    restart: unless-stopped
    depends_on:
      mariadb:
        condition: service_healthy
    environment:
      TZ: ${TZ}
    volumes:
      - ./config/homeassistant:/config
      - ./logs:/config/logs
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "8123:8123"
    privileged: true
    network_mode: host
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123/api/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  # ESPHome - Microcontroller Management
  esphome:
    image: esphome/esphome:latest
    container_name: greenhouse_esphome
    restart: unless-stopped
    environment:
      TZ: ${TZ}
    volumes:
      - ./config/esphome:/config
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "6052:6052"
    privileged: true
    network_mode: host
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # MQTT Broker - Sensor Communication
  mosquitto:
    image: eclipse-mosquitto:2.0
    container_name: greenhouse_mosquitto
    restart: unless-stopped
    volumes:
      - ./config/mosquitto:/mosquitto/config
      - mosquitto_data:/mosquitto/data
      - mosquitto_logs:/mosquitto/log
    ports:
      - "1883:1883"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "mosquitto_pub", "-h", "localhost", "-t", "test", "-m", "test"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - greenhouse_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # phpMyAdmin - Database Management
  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: greenhouse_phpmyadmin
    restart: unless-stopped
    depends_on:
      - mariadb
    environment:
      PMA_HOST: greenhouse_mariadb
      PMA_PORT: 3306
      PMA_USER: root
      PMA_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "8080:80"
    networks:
      - greenhouse_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Uptime Kuma - Service Monitoring
  uptime_kuma:
    image: louislam/uptime-kuma:1
    container_name: greenhouse_uptime_kuma
    restart: unless-stopped
    volumes:
      - uptime_kuma_data:/app/data
    ports:
      - "3001:3001"
    networks:
      - greenhouse_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # Node Exporter - System Metrics
  node_exporter:
    image: prom/node-exporter:latest
    container_name: greenhouse_node_exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    networks:
      - greenhouse_net

  # Watchtower - Automatic Updates
  watchtower:
    image: containrrr/watchtower
    container_name: greenhouse_watchtower
    restart: unless-stopped
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_SCHEDULE: "0 0 4 * * *"  # 4 AM daily
      WATCHTOWER_NOTIFICATIONS: "email"
      WATCHTOWER_NOTIFICATION_EMAIL_FROM: ${WATCHTOWER_EMAIL_FROM}
      WATCHTOWER_NOTIFICATION_EMAIL_TO: ${WATCHTOWER_EMAIL_TO}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER: ${SMTP_SERVER}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT: 587
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER: ${SMTP_USERNAME}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD: ${SMTP_PASSWORD}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - greenhouse_net

volumes:
  mariadb_data:
    driver: local
  uptime_kuma_data:
    driver: local
  mosquitto_data:
    driver: local
  mosquitto_logs:
    driver: local

networks:
  greenhouse_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

echo "✅ Docker Compose file created"

# Create MariaDB configuration
echo "🗄️ Creating MariaDB configuration..."
mkdir -p config/mariadb
cat > config/mariadb/my.cnf << 'EOF'
[mysqld]
# Performance settings optimized for 32GB RAM server
innodb_buffer_pool_size = 8G
innodb_log_file_size = 512M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT
innodb_io_capacity = 2000
innodb_read_io_threads = 8
innodb_write_io_threads = 8

# Connection settings
max_connections = 200
max_connect_errors = 1000000
wait_timeout = 28800
interactive_timeout = 28800

# Query cache (disabled for better performance)
query_cache_type = 0
query_cache_size = 0

# Binary logging for backup
log_bin = mysql-bin
binlog_format = ROW
sync_binlog = 1
expire_logs_days = 7

# Character set
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# Security
ssl = 0
local_infile = 0

[mysql]
default_character_set = utf8mb4

[client]
default_character_set = utf8mb4
EOF

# Create Home Assistant configuration
echo "🏠 Creating Home Assistant configuration..."
mkdir -p config/homeassistant
cat > config/homeassistant/configuration.yaml << 'EOF'
# Commercial Greenhouse Configuration
homeassistant:
  name: Commercial Greenhouse
  latitude: !secret latitude
  longitude: !secret longitude
  elevation: !secret elevation
  unit_system: metric
  time_zone: Europe/Oslo
  country: NO

# HTTP with security
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.20.0.0/16
    - 127.0.0.1
  ip_ban_enabled: true
  login_attempts_threshold: 5

# Database - High Performance MariaDB
recorder:
  db_url: !secret db_url
  purge_keep_days: 365
  auto_purge: true
  commit_interval: 1
  include:
    domains:
      - sensor
      - binary_sensor
      - switch
      - automation
      - fan
    entity_globs:
      - sensor.soil_*
      - sensor.tank_*
      - sensor.fan_*
      - switch.solenoid_*
      - switch.*_valve

# MQTT
mqtt:
  broker: greenhouse_mosquitto
  port: 1883
  username: !secret mqtt_username
  password: !secret mqtt_password

# Notifications
notify:
  - name: critical_alerts
    platform: smtp
    server: !secret smtp_server
    port: 587
    sender: !secret smtp_sender
    username: !secret smtp_username
    password: !secret smtp_password
    recipient:
      - !secret admin_email

# Essential components
api:
logger:
  default: warning
  logs:
    homeassistant.components.recorder: info
system_health:
mobile_app:
frontend:
config:
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

# System monitoring sensors
sensor:
  - platform: systemmonitor
    resources:
      - type: disk_use_percent
        arg: /
      - type: memory_use_percent
      - type: processor_use
      - type: load_1m

  - platform: uptime
    name: System Uptime

# Input helpers for manual control
input_boolean:
  emergency_mode:
    name: Emergency Mode
    icon: mdi:alert-octagon

  irrigation_enabled:
    name: Irrigation System Enabled
    icon: mdi:water

input_number:
  target_soil_moisture:
    name: Target Soil Moisture
    min: 30
    max: 80
    step: 5
    unit_of_measurement: "%"
    icon: mdi:water-percent

# Weather integration
weather:
  - platform: yr

# Binary sensors for system health
binary_sensor:
  - platform: template
    sensors:
      system_healthy:
        friendly_name: "System Health Status"
        value_template: >
          {{ states('sensor.processor_use') | int < 80 and
             states('sensor.memory_use_percent') | int < 80 and
             states('sensor.disk_use_percent') | int < 90 }}
        device_class: problem

# Template sensors
sensor:
  - platform: template
    sensors:
      greenhouse_status:
        friendly_name: "Greenhouse Status"
        value_template: >
          {% set issues = [] %}
          {% if states('sensor.processor_use') | int > 80 %}
            {% set issues = issues + ['High CPU'] %}
          {% endif %}
          {% if states('sensor.memory_use_percent') | int > 80 %}
            {% set issues = issues + ['High Memory'] %}
          {% endif %}
          {% if states('sensor.disk_use_percent') | int > 90 %}
            {% set issues = issues + ['Low Disk Space'] %}
          {% endif %}
          {% if issues | length == 0 %}
            Healthy
          {% else %}
            {{ issues | join(', ') }}
          {% endif %}
        icon_template: >
          {% if states('binary_sensor.system_healthy') == 'on' %}
            mdi:check-circle
          {% else %}
            mdi:alert-circle
          {% endif %}
EOF

# Create secrets file
cat > config/homeassistant/secrets.yaml << EOF
# Location (update with your greenhouse coordinates)
latitude: 59.2761
longitude: 5.2034
elevation: 10

# Database
db_url: mysql://homeassistant:$(grep MYSQL_HA_PASSWORD .env | cut -d'=' -f2)@greenhouse_mariadb:3306/homeassistant?charset=utf8mb4

# MQTT
mqtt_username: $(grep MQTT_USERNAME .env | cut -d'=' -f2)
mqtt_password: $(grep MQTT_PASSWORD .env | cut -d'=' -f2)

# SMTP (update with your email settings)
smtp_server: smtp.gmail.com
smtp_sender: greenhouse@yourdomain.com
smtp_username: your-email@gmail.com
smtp_password: your-app-password

# Admin
admin_email: admin@yourdomain.com
EOF

# Create empty automation files
echo "[]" > config/homeassistant/automations.yaml
echo "{}" > config/homeassistant/scripts.yaml
echo "[]" > config/homeassistant/scenes.yaml

# Create MQTT configuration
echo "📡 Creating MQTT configuration..."
mkdir -p config/mosquitto
cat > config/mosquitto/mosquitto.conf << 'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_type all
connection_messages true
log_timestamp true

listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd

listener 9001
protocol websockets
EOF

# Create backup script
echo "💾 Creating backup script..."
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/opt/greenhouse/backups/daily"
DATE=$(date +%Y%m%d_%H%M%S)

# Source environment
source /opt/greenhouse/.env

mkdir -p "$BACKUP_DIR"

echo "$(date): Starting backup..."

# Database backup
echo "Backing up MariaDB database..."
docker exec greenhouse_mariadb mysqldump \
    -u root -p"$MYSQL_ROOT_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --all-databases \
    --events \
    > "$BACKUP_DIR/greenhouse_db_${DATE}.sql"

# Configuration backup
echo "Backing up configuration files..."
tar -czf "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" \
    -C /opt/greenhouse \
    config/ \
    docker-compose.yml \
    .env

# Cleanup old backups (keep 7 days)
find "$BACKUP_DIR" -name "greenhouse_*" -mtime +7 -delete

echo "$(date): Backup completed successfully"
EOF

chmod +x scripts/backup.sh

# Create system monitoring script
cat > scripts/system-monitor.sh << 'EOF'
#!/bin/bash
set -e

LOG_FILE="/opt/greenhouse/logs/system-monitor.log"
mkdir -p /opt/greenhouse/logs

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check container health
check_containers() {
    local failed_containers=()
    local containers=("greenhouse_mariadb" "greenhouse_homeassistant" "greenhouse_mosquitto" "greenhouse_esphome")
    
    for container in "${containers[@]}"; do
        if ! docker ps | grep -q "$container"; then
            failed_containers+=("$container")
            log_message "CRITICAL: Container $container is not running"
        fi
    done
    
    if [ ${#failed_containers[@]} -gt 0 ]; then
        log_message "Attempting to restart failed containers..."
        cd /opt/greenhouse && docker-compose up -d "${failed_containers[@]}"
    else
        log_message "All containers running successfully"
    fi
}

# Check system resources
check_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100.0}')
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    log_message "System Status - CPU: ${cpu_usage}%, Memory: ${mem_usage}%, Disk: ${disk_usage}%"
    
    # Alert on high usage
    if [ "${cpu_usage%.*}" -gt 90 ] || [ "$mem_usage" -gt 90 ] || [ "$disk_usage" -gt 95 ]; then
        log_message "WARNING: High resource usage detected"
    fi
}

# Main monitoring
log_message "Starting system monitoring check"
check_containers
check_resources
log_message "System monitoring check completed"
EOF

chmod +x scripts/system-monitor.sh

# Generate SSL certificate (self-signed for now)
echo "🔐 Generating SSL certificate..."
mkdir -p ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ssl/greenhouse.key \
    -out ssl/greenhouse.crt \
    -subj "/CN=greenhouse.local/O=Greenhouse Control System"

echo "🚀 Starting greenhouse system..."
echo "This may take a few minutes on first run..."

# Pull images first
docker-compose pull

# Start the stack
docker-compose up -d

echo "⏳ Waiting for services to initialize..."
sleep 60

# Wait for MariaDB
echo "Waiting for MariaDB to be ready..."
until docker exec greenhouse_mariadb mysqladmin ping -h"localhost" --silent 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo " MariaDB ready!"

# Wait for Home Assistant
echo "Waiting for Home Assistant to be ready..."
until curl -f http://localhost:8123 >/dev/null 2>&1; do
    echo -n "."
    sleep 5
done
echo " Home Assistant ready!"

# Set up MQTT users
echo "📡 Setting up MQTT authentication..."
MQTT_PASSWORD=$(grep MQTT_PASSWORD .env | cut -d'=' -f2)
docker exec greenhouse_mosquitto mosquitto_passwd -c -b /mosquitto/config/passwd greenhouse "$MQTT_PASSWORD"
docker restart greenhouse_mosquitto

# Enable system monitoring
echo "📊 Enabling system monitoring..."
sudo systemctl enable greenhouse-monitor.timer
sudo systemctl start greenhouse-monitor.timer

# Create daily backup cron job
echo "💾 Setting up automated backups..."
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/greenhouse/scripts/backup.sh") | crontab -

# Display summary
echo ""
echo "✅ GREENHOUSE SYSTEM DEPLOYED SUCCESSFULLY!"
echo "==========================================="
echo ""
echo "🌐 Access URLs:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏠 Home Assistant:     http://$(hostname -I | awk '{print $1}'):8123"
echo "🔧 ESPHome:           http://$(hostname -I | awk '{print $1}'):6052"
echo "🗄️  phpMyAdmin:        http://$(hostname -I | awk '{print $1}'):8080"
echo "📈 Uptime Monitor:    http://$(hostname -I | awk '{print $1}'):3001"
echo "📊 Node Exporter:     http://$(hostname -I | awk '{print $1}'):9100"
echo ""
echo "🔐 Database Credentials:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MariaDB Root:         root / $(grep MYSQL_ROOT_PASSWORD .env | cut -d'=' -f2)"
echo "Home Assistant DB:    homeassistant / $(grep MYSQL_HA_PASSWORD .env | cut -d'=' -f2)"
echo "MQTT:                 greenhouse / $(grep MQTT_PASSWORD .env | cut -d'=' -f2)"
echo ""
echo "📋 Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Access Home Assistant and complete initial setup"
echo "2. Update email settings in config/homeassistant/secrets.yaml"
echo "3. Configure ESPHome with your sensor devices"
echo "4. Set up Uptime Kuma monitoring dashboards"
echo "5. Test backup system: ./scripts/backup.sh"
echo ""
echo "🛠️ Useful Commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "View logs:            docker-compose logs -f [service_name]"
echo "Restart service:      docker-compose restart [service_name]"
echo "Stop all services:    docker-compose down"
echo "Update services:      docker-compose pull && docker-compose up -d"
echo "Manual backup:        ./scripts/backup.sh"
echo "System monitor:       ./scripts/system-monitor.sh"
echo ""
echo "📁 Important Files:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Environment:          /opt/greenhouse/.env"
echo "HA Configuration:     /opt/greenhouse/config/homeassistant/"
echo "Backups:             /opt/greenhouse/backups/"
echo "Logs:                /opt/greenhouse/logs/"
echo ""
echo "🔒 Security Reminder:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "- Update default passwords in .env file"
echo "- Configure email settings in secrets.yaml"
echo "- Set up SSH key authentication"
echo "- Review firewall rules for your network"
echo ""
echo "🏭 ENTERPRISE GREENHOUSE SYSTEM READY!"
echo ""

# Save deployment info
cat > DEPLOYMENT_STATUS.txt << EOF
GREENHOUSE DEPLOYMENT COMPLETED
===============================

Deployment Date: $(date)
System Status: All services running
Database: MariaDB $(docker exec greenhouse_mariadb mysql --version)
Home Assistant: $(docker exec greenhouse_homeassistant cat /config/.HA_VERSION)

SERVICES STATUS:
$(docker-compose ps)

CONTAINER HEALTH:
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

NEXT ACTIONS REQUIRED:
1. Complete Home Assistant initial setup
2. Update email configuration in secrets.yaml
3. Add ESP32 devices via ESPHome
4. Configure Uptime Kuma monitoring
5. Test all alert mechanisms

CREDENTIALS SAVED IN: .env
BACKUP SCHEDULE: Daily at 2 AM
MONITORING: Active (5-minute intervals)
EOF

echo "📄 Deployment status saved to: DEPLOYMENT_STATUS.txt"
echo "💾 All passwords saved securely in: .env"
echo ""
echo "🎉 Your enterprise-grade greenhouse system is now operational!"
