#!/bin/bash

#==========================================
# Wazuh Backup Retention Cleanup Script
#==========================================

# Folder where backups are stored
BACKUP_DIR="/root"

# Keep backups for this many days
RETENTION_DAYS=7

echo "-----------------------------------"
echo " Wazuh Backup Retention Cleanup"
echo "-----------------------------------"
echo "Backup directory: $BACKUP_DIR"
echo "Retention days: $RETENTION_DAYS"
echo ""

# Find and delete old backups
find "$BACKUP_DIR" -maxdepth 1 \
    -type d -name "wazuh_backup_*" \
    -mtime +$RETENTION_DAYS \
    -exec rm -rf {} \; -print

find "$BACKUP_DIR" -maxdepth 1 \
    -type f -name "wazuh_backup_*.tar.gz" \
    -mtime +$RETENTION_DAYS \
    -exec rm -f {} \; -print

echo "Cleanup completed."
