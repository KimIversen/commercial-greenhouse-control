#!/bin/bash
# Greenhouse Backup Script
# Backs up database and config. Runs daily via cron.

set -e

BACKUP_DIR="/opt/greenhouse/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

source /opt/greenhouse/.env

mkdir -p "$BACKUP_DIR"

echo "$(date): Starting backup..."

# Database backup
docker exec greenhouse_mariadb mysqldump \
    -u root -p"$MYSQL_ROOT_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --all-databases \
    | gzip > "$BACKUP_DIR/db_${DATE}.sql.gz"

# Verify backup
if ! gzip -t "$BACKUP_DIR/db_${DATE}.sql.gz" 2>/dev/null; then
    echo "ERROR: Database backup is corrupt"
    exit 1
fi

# Config backup (excludes secrets and runtime data)
tar -czf "$BACKUP_DIR/config_${DATE}.tar.gz" \
    -C /opt/greenhouse \
    --exclude='config/homeassistant/.storage' \
    --exclude='config/homeassistant/home-assistant_v2.db*' \
    --exclude='config/homeassistant/tts' \
    --exclude='config/esphome/.esphome' \
    config/ \
    docker-compose.yml

# Upload to Google Drive if rclone is configured
if command -v rclone &>/dev/null && rclone listremotes 2>/dev/null | grep -q "gdrive:"; then
    rclone copy "$BACKUP_DIR/db_${DATE}.sql.gz" gdrive:greenhouse-backups/
    rclone copy "$BACKUP_DIR/config_${DATE}.tar.gz" gdrive:greenhouse-backups/
    echo "$(date): Uploaded to Google Drive"
fi

# Cleanup old local backups
find "$BACKUP_DIR" -name "db_*" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "config_*" -mtime +$RETENTION_DAYS -delete

echo "$(date): Backup complete"
