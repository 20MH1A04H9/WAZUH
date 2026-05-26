#!/bin/bash

# ===========================
# WAZUH FULL BACKUP SCRIPT
# ===========================

# Backup folder
bkp_folder="/root/wazuh_backup_$(date +%F_%H-%M)"
mkdir -p "$bkp_folder/server"

echo "📁 Backup folder: $bkp_folder"
echo "⏳ Starting backup..."

# ---- Save Host Info ----
cat /etc/*release* > "$bkp_folder/host-info.txt"
echo -e "\n$(hostname): $(hostname -I)" >> "$bkp_folder/host-info.txt"

# ---- Start RSYNC Backup ----
rsync -aREzh --info=progress2 --progress \
  /etc/filebeat/ \
  /var/ossec/api/configuration/ \
  /var/ossec/etc/client.keys \
  /var/ossec/etc/sslmanager* \
  /var/ossec/etc/ossec.conf \
  /var/ossec/etc/internal_options.conf \
  /var/ossec/etc/local_internal_options.conf \
  /var/ossec/etc/rules/ \
  /var/ossec/etc/decoders/ \
  /var/ossec/etc/shared/ \
  /var/ossec/logs/ \
  /var/ossec/stats/ \
  "$bkp_folder/server/"

# ---- Create Compressed File ----
cd /root
tar -czf "wazuh_backup_$(date +%F_%H-%M).tar.gz" "$(basename "$bkp_folder")"

echo "✅ Backup completed!"
echo "📦 Archive created: /root/wazuh_backup_$(date +%F_%H-%M).tar.gz"
echo "✨ You can restore using rsync or extract the archive."
