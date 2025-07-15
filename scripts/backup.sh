#!/bin/bash
# Enhanced Greenhouse System Backup Script with Google Drive Upload
# Automated backup of database and configuration files with cloud storage

set -e

BACKUP_DIR="/opt/greenhouse/backups/daily"
DATE=$(date +%Y%m%d_%H%M%S)
GDRIVE_FOLDER="greenhouse-backups"
RETENTION_LOCAL=7  # Keep 7 days locally
RETENTION_GDRIVE=90  # Keep 90 days on Google Drive

# Source environment variables
if [ -f /opt/greenhouse/.env ]; then
    source /opt/greenhouse/.env
else
    echo "Error: .env file not found"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

log_backup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$BACKUP_DIR/backup.log"
}

log_backup "Starting backup process..."

# Database backup with compression
log_backup "Backing up MariaDB database..."
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
    log_backup "ERROR: Database backup verification failed"
    exit 1
fi

# Configuration backup
log_backup "Backing up configuration files..."
tar -czf "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" \
    -C /opt/greenhouse \
    config/ \
    docker-compose.yml \
    .env \
    Makefile

# ESPHome configurations backup
if [ -d /opt/greenhouse/config/esphome ]; then
    tar -czf "$BACKUP_DIR/greenhouse_esphome_${DATE}.tar.gz" \
        -C /opt/greenhouse \
        config/esphome/
fi

# System info backup
log_backup "Creating system information backup..."
cat > "$BACKUP_DIR/system_info_${DATE}.txt" << EOF
Backup Date: $(date)
Hostname: $(hostname)
System: $(uname -a)
Docker Version: $(docker --version)
Docker Compose Version: $(docker-compose --version)
Disk Usage: $(df -h /)
Memory: $(free -h)
Container Status:
$(docker-compose ps)
EOF

# Calculate backup sizes
DB_SIZE=$(du -h "$BACKUP_DIR/greenhouse_db_${DATE}.sql" | cut -f1)
CONFIG_SIZE=$(du -h "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" | cut -f1)

log_backup "Local backup completed - Database: $DB_SIZE, Config: $CONFIG_SIZE"

# Upload to Google Drive (if rclone is configured)
if command -v rclone >/dev/null 2>&1; then
    log_backup "Uploading backups to Google Drive..."
    
    # Check if Google Drive is configured
    if rclone listremotes | grep -q "gdrive:"; then
        # Create backup folder on Google Drive if it doesn't exist
        rclone mkdir gdrive:$GDRIVE_FOLDER 2>/dev/null || true
        
        # Upload database backup
        if rclone copy "$BACKUP_DIR/greenhouse_db_${DATE}.sql" gdrive:$GDRIVE_FOLDER/; then
            log_backup "✅ Database backup uploaded to Google Drive"
        else
            log_backup "❌ Failed to upload database backup to Google Drive"
        fi
        
        # Upload config backup
        if rclone copy "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" gdrive:$GDRIVE_FOLDER/; then
            log_backup "✅ Config backup uploaded to Google Drive"
        else
            log_backup "❌ Failed to upload config backup to Google Drive"
        fi
        
        # Upload system info
        if rclone copy "$BACKUP_DIR/system_info_${DATE}.txt" gdrive:$GDRIVE_FOLDER/; then
            log_backup "✅ System info uploaded to Google Drive"
        else
            log_backup "❌ Failed to upload system info to Google Drive"
        fi
        
        # Upload ESPHome backup if it exists
        if [ -f "$BACKUP_DIR/greenhouse_esphome_${DATE}.tar.gz" ]; then
            if rclone copy "$BACKUP_DIR/greenhouse_esphome_${DATE}.tar.gz" gdrive:$GDRIVE_FOLDER/; then
                log_backup "✅ ESPHome backup uploaded to Google Drive"
            else
                log_backup "❌ Failed to upload ESPHome backup to Google Drive"
            fi
        fi
        
        # Cleanup old backups on Google Drive (keep last 90 days)
        log_backup "Cleaning up old Google Drive backups..."
        CUTOFF_DATE=$(date -d "$RETENTION_GDRIVE days ago" +%Y%m%d)
        
        # List and delete old files
        rclone lsf gdrive:$GDRIVE_FOLDER/ | while read file; do
            # Extract date from filename (assumes format: greenhouse_*_YYYYMMDD_*.*)
            FILE_DATE=$(echo "$file" | grep -oE '[0-9]{8}' | head -1)
            if [ ! -z "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
                if rclone delete "gdrive:$GDRIVE_FOLDER/$file"; then
                    log_backup "Deleted old Google Drive backup: $file"
                fi
            fi
        done
        
    else
        log_backup "Google Drive not configured. Run 'rclone config' to set up."
    fi
elif command -v gdrive >/dev/null 2>&1; then
    log_backup "Uploading backups to Google Drive using gdrive..."
    
    # Upload files to Google Drive
    DB_UPLOAD=$(gdrive upload "$BACKUP_DIR/greenhouse_db_${DATE}.sql" --parent-name "$GDRIVE_FOLDER" 2>/dev/null | grep "Uploaded" | awk '{print $2}')
    if [ ! -z "$DB_UPLOAD" ]; then
        log_backup "✅ Database backup uploaded to Google Drive (ID: $DB_UPLOAD)"
    else
        log_backup "❌ Failed to upload database backup to Google Drive"
    fi
    
    CONFIG_UPLOAD=$(gdrive upload "$BACKUP_DIR/greenhouse_config_${DATE}.tar.gz" --parent-name "$GDRIVE_FOLDER" 2>/dev/null | grep "Uploaded" | awk '{print $2}')
    if [ ! -z "$CONFIG_UPLOAD" ]; then
        log_backup "✅ Config backup uploaded to Google Drive (ID: $CONFIG_UPLOAD)"
    else
        log_backup "❌ Failed to upload config backup to Google Drive"
    fi
else
    log_backup "No Google Drive upload tool found. Install rclone or gdrive for cloud backup."
fi

# Cleanup old local backups
if [[ "$BACKUP_DIR" == *"daily"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +$RETENTION_LOCAL -delete
    log_backup "Cleaned up local backups older than $RETENTION_LOCAL days"
elif [[ "$BACKUP_DIR" == *"weekly"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +28 -delete
    log_backup "Cleaned up local backups older than 28 days"
elif [[ "$BACKUP_DIR" == *"monthly"* ]]; then
    find "$BACKUP_DIR" -name "greenhouse_*" -mtime +365 -delete
    log_backup "Cleaned up local backups older than 365 days"
fi

# Create backup summary
TOTAL_LOCAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log_backup "Backup process completed successfully"
log_backup "Local backup size: $TOTAL_LOCAL_SIZE"
log_backup "Database: $DB_SIZE, Config: $CONFIG_SIZE"

# Send backup notification email (if configured)
if command -v mail >/dev/null 2>&1 && [ ! -z "$WATCHTOWER_EMAIL_TO" ]; then
    {
        echo "🏭 Greenhouse Backup Report - $(date)"
        echo "=================================="
        echo ""
        echo "✅ Backup Status: SUCCESS"
        echo "📅 Date: $(date)"
        echo "💾 Database Size: $DB_SIZE"
        echo "⚙️ Config Size: $CONFIG_SIZE"
        echo "📂 Total Local Size: $TOTAL_LOCAL_SIZE"
        echo "📍 Location: $BACKUP_DIR"
        echo ""
        if command -v rclone >/dev/null 2>&1 && rclone listremotes | grep -q "gdrive:"; then
            echo "☁️ Google Drive: UPLOADED"
        else
            echo "☁️ Google Drive: NOT CONFIGURED"
        fi
        echo ""
        echo "Recent backups:"
        ls -la "$BACKUP_DIR" | tail -5
    } | mail -s "🏭 Greenhouse Backup Completed - $(date +%Y-%m-%d)" "$WATCHTOWER_EMAIL_TO"
fi

log_backup "All backup operations completed"
