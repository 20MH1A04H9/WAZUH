#!/bin/bash
 
echo "========================================="
echo " Wazuh Dashboard SSL Auto Configuration "
echo "========================================="
 
# Ask user for domain
read -p "Enter your domain name (ex: security.yourdomain.com): " DOMAIN
 
# Update system
sudo apt update -y && sudo apt upgrade -y
 
# Install Certbot
sudo apt install certbot -y
 
# Stop Wazuh Dashboard before certbot uses port 80
sudo systemctl stop wazuh-dashboard
 
# Generate SSL Certificate
sudo certbot certonly --standalone -d $DOMAIN --agree-tos --register-unsafely-without-email
 
# Create Wazuh cert directory
sudo mkdir -p /etc/wazuh-dashboard/certs/
 
# Copy Certs
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/wazuh-dashboard/certs/
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/wazuh-dashboard/certs/
 
# Set Permissions (as you confirmed working)
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/
sudo chmod -R 500 /etc/wazuh-dashboard/certs/
sudo chmod 440 /etc/wazuh-dashboard/certs/privkey.pem /etc/wazuh-dashboard/certs/fullchain.pem
 
# Update Wazuh Dashboard Config
sudo sed -i "s#^server\.ssl\.enabled:.*#server.ssl.enabled: true#g" /etc/wazuh-dashboard/opensearch_dashboards.yml
sudo sed -i "s#^server\.ssl\.certificate:.*#server.ssl.certificate: /etc/wazuh-dashboard/certs/fullchain.pem#g" /etc/wazuh-dashboard/opensearch_dashboards.yml
sudo sed -i "s#^server\.ssl\.key:.*#server.ssl.key: /etc/wazuh-dashboard/certs/privkey.pem#g" /etc/wazuh-dashboard/opensearch_dashboards.yml
 
# Restart Services
sudo systemctl daemon-reload
sudo systemctl restart wazuh-dashboard
 
# Auto renew setup
echo "0 3 * * * /usr/bin/certbot renew --quiet && systemctl restart wazuh-dashboard" | sudo tee /etc/cron.d/wazuh-ssl-renew > /dev/null
 
echo "========================================="
echo " ✅ SSL Installed Successfully!"
echo " Open https://$DOMAIN in your browser"
echo "========================================="
