#!/bin/bash
# Enterprise Greenhouse Server Setup Script v2 (Fixed)
# Run as root on Ubuntu Server 22.04 LTS
# This version starts from directory creation (line 97+)

set -e  # Exit on any error

echo "🏭 ENTERPRISE GREENHOUSE SERVER SETUP v2"
echo "========================================"
echo "Continuing installation from directory creation..."
echo ""

# Check if we're root
if [ "$EUID" -ne 0 ]; then
    echo "❌ ERROR: This script must be run as root"
    echo "Please run: sudo ./server-setup-v2.sh"
    exit 1
fi

# Check if greenhouse user exists (should have been created in v1)
if ! id "greenhouse" &>/dev/null; then
    echo "👤 Creating greenhouse user..."
    useradd -m -s /bin/bash -G docker,sudo greenhouse
    echo "Set password for greenhouse user:"
    passwd greenhouse
else
    echo "✅ Greenhouse user already exists"
fi

# Create directory structure (FIXED VERSION)
echo "📁 Creating directory structure..."
mkdir -p /opt/greenhouse/config/homeassistant
mkdir -p /opt/greenhouse/config/mariadb
mkdir -p /opt/greenhouse/config/mosquitto
mkdir -p /opt/greenhouse/config/nginx
mkdir -p /opt/greenhouse/config/esphome
mkdir -p /opt/greenhouse/data
mkdir -p /opt/greenhouse/backups/daily
mkdir -p /opt/greenhouse/backups/weekly
mkdir -p /opt/greenhouse/backups/monthly
mkdir -p /opt/greenhouse/logs
mkdir -p /opt/greenhouse/scripts
mkdir -p /opt/greenhouse/ssl

# Set proper permissions
echo "🔒 Setting permissions..."
chown -R greenhouse:greenhouse /opt/greenhouse
chmod -R 755 /opt/greenhouse

# Configure SSH security
echo "🔐 Hardening SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# SSH hardening configuration
cat > /etc/ssh/sshd_config << 'EOF'
# Greenhouse Server SSH Configuration - Security Hardened

# Basic settings
Port 22
Protocol 2
AddressFamily inet

# Authentication
PermitRootLogin no
PasswordAuthentication yes  # Will disable after key setup
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow only greenhouse users
AllowUsers greenhouse greenhouse-admin

# Disable dangerous features
X11Forwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Banner
Banner /etc/ssh/banner
EOF

# Create SSH banner
cat > /etc/ssh/banner << 'EOF'
*********************************************************************
*                   GREENHOUSE CONTROL SYSTEM                      *
*                                                                   *
*   WARNING: This system controls critical greenhouse operations   *
*   Unauthorized access is prohibited and monitored               *
*   All activities are logged                                     *
*                                                                   *
*********************************************************************
EOF

systemctl restart ssh

# Configure fail2ban for additional security
echo "🛡️ Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Configure automatic security updates
echo "🔄 Configuring automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF

# Enable automatic updates
systemctl enable unattended-upgrades

# Configure system monitoring
echo "📊 Setting up system monitoring..."
cat > /etc/systemd/system/greenhouse-monitor.service << 'EOF'
[Unit]
Description=Greenhouse System Monitor
After=network.target docker.service

[Service]
Type=oneshot
User=greenhouse
ExecStart=/opt/greenhouse/scripts/system-monitor.sh
WorkingDirectory=/opt/greenhouse

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/greenhouse-monitor.timer << 'EOF'
[Unit]
Description=Run Greenhouse System Monitor every 5 minutes
Requires=greenhouse-monitor.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Configure log rotation
echo "📝 Configuring log rotation..."
cat > /etc/logrotate.d/greenhouse << 'EOF'
/opt/greenhouse/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 greenhouse greenhouse
    postrotate
        /usr/bin/docker kill -s USR1 greenhouse_homeassistant 2>/dev/null || true
    endscript
}

/var/log/docker/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
}
EOF

# Enable services
systemctl enable docker
systemctl start docker

# Add greenhouse user to docker group (in case it wasn't added)
usermod -aG docker greenhouse

# System optimization for greenhouse operations
echo "⚡ Optimizing system for greenhouse operations..."

# Increase file watchers for Home Assistant
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf

# Optimize network settings
cat >> /etc/sysctl.conf << 'EOF'

# Network optimizations for IoT devices
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr

# Reduce swap usage (important for database performance)
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl -p

# Create installation summary
cat > /opt/greenhouse/INSTALLATION_SUMMARY.txt << EOF
GREENHOUSE SERVER INSTALLATION COMPLETED
========================================

Installation Date: $(date)
Server OS: Ubuntu $(lsb_release -rs) LTS
Docker Version: $(docker --version)
Docker Compose Version: $(docker-compose --version)

SECURITY CONFIGURATION:
- Firewall: UFW enabled with restricted access
- SSH: Hardened configuration, root login disabled
- Fail2ban: Active monitoring for intrusion attempts
- Auto-updates: Security updates enabled

DIRECTORY STRUCTURE:
/opt/greenhouse/
├── config/          # Service configurations
├── data/           # Application data
├── backups/        # Automated backups
├── logs/           # System logs
├── scripts/        # Maintenance scripts
└── ssl/            # SSL certificates

NEXT STEPS:
1. Switch to greenhouse user: sudo su - greenhouse
2. Set up SSH keys for secure access
3. Deploy the greenhouse Docker stack
4. Configure Home Assistant and sensors

IMPORTANT PORTS:
- SSH: 22
- Home Assistant: 8123
- MQTT: 1883
- ESPHome: 6052
- MariaDB: 3306
- phpMyAdmin: 8080
- Monitoring: 3001

GREENHOUSE USER CREATED:
Username: greenhouse
Groups: docker, sudo
Home: /home/greenhouse
EOF

chown greenhouse:greenhouse /opt/greenhouse/INSTALLATION_SUMMARY.txt

echo ""
echo "✅ SERVER SETUP v2 COMPLETED!"
echo "=============================="
echo ""
echo "📋 Installation Summary:"
echo "- Directory structure created and fixed"
echo "- SSH security hardened"
echo "- System monitoring configured"
echo "- Docker ready for greenhouse stack"
echo ""
echo "📁 All files are in: /opt/greenhouse/"
echo "📄 Full summary: /opt/greenhouse/INSTALLATION_SUMMARY.txt"
echo ""
echo "🚀 NEXT STEP: Deploy the greenhouse Docker stack"
echo "   Switch to greenhouse user: sudo su - greenhouse"
echo "   Then run the deployment script"
echo ""
echo "💡 TIP: Reboot the server to ensure all optimizations are active"
echo "   sudo reboot"
EOF
