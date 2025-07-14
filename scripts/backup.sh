#!/bin/bash
# Greenhouse System Backup Script
# Automated backup of database and configuration files

set -e

BACKUP_DIR="/opt/greenhouse/backups/daily"
DATE=$(date +%Y%m%d_%H%M%S)

# Source environment variables
if [ -f /opt/greenhouse/.env ]; then
    source /opt/greenhouse/.env
else
    echo "Error: .env file not found"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "$(date): Starting backup process..."

# Database backup with compression
echo "Backing up MariaDB database..."
docker exec greenhouse_mariadb mysqldump \
    -u root -p"$MYSQL_ROOT_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --all-databases \
    --events \
    --compress \
    > "$BACKUP_DIR/greenhouse_db_${DATE}.sql"

# Verify database backup
if ! grep -q "CREATE DATABASE" "$BACKUP_DIR/greenhouse_db_${DATE}.sql"; then
    echo "ERROR: Database backup verification failed"
    exit 1
fi

# Configuration backup
echo "Backing up configuration files..."
tar -czf "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" \
    -C /opt/greenhouse \
    config/ \
    docker-compose.yml \
    .env

# ESPHome configurations backup
if [ -d /opt/greenhouse/config/esphome ]; then
    tar -czf "$BACKUP_DIR/greenhouse_esphome_${DATE}.tar.gz" \
        -C /opt/greenhouse \
        config/esphome/
fi

# Calculate backup sizes
DB_SIZE=$(du -h "$BACKUP_DIR/greenhouse_db_${DATE}.sql" | cut -f1)
CONFIG_SIZE=$(du -h "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" | cut -f1)

echo "Backup sizes - Database: $DB_SIZE, Config: $CONFIG_SIZE"

# Cleanup old backups (keep 30 days for daily, 4 weeks for weekly, 12 months for monthly)
if [[ "$BACKUP_DIR" == *"daily"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +30 -delete
elif [[ "$BACKUP_DIR" == *"weekly"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +28 -delete
elif [[ "$BACKUP_DIR" == *"monthly"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +365 -delete
fi

# Log backup completion
echo "$(date): Backup completed successfully"
echo "Database backup: $BACKUP_DIR/greenhouse_db_${DATE}.sql ($DB_SIZE)"
echo "Config backup: $BACKUP_DIR/greenhouse_config_${DATE}.tar.gz ($CONFIG_SIZE)"

# Optional: Send backup notification email
if command -v mail >/dev/null 2>&1 && [ ! -z "$WATCHTOWER_EMAIL_TO" ]; then
    {
        echo "Greenhouse Backup Report"
        echo "Date: $(date)"
        echo "Database Size: $DB_SIZE"
        echo "Config Size: $CONFIG_SIZE"
        echo "Location: $BACKUP_DIR"
        echo ""
        echo "Backup completed successfully."
    } | mail -s "Greenhouse Backup Completed" "$WATCHTOWER_EMAIL_TO"
fi
