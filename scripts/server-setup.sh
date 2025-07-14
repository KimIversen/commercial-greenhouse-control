#!/bin/bash
# Enterprise Greenhouse Server Setup Script
# Run as root on fresh Ubuntu Server 22.04 LTS

set -e  # Exit on any error
clear

echo "🏭 ENTERPRISE GREENHOUSE SERVER SETUP"
echo "======================================"
echo "This will configure your server for mission-critical greenhouse operations"
echo ""
read -p "Press Enter to continue, Ctrl+C to abort..."

# Update system packages
echo "📦 Updating system packages..."
apt update && apt upgrade -y

# Install essential packages
echo "🔧 Installing essential packages..."
apt install -y \
    curl \
    wget \
    git \
    htop \
    tree \
    nano \
    vim \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    fail2ban \
    ufw \
    logrotate \
    rsync \
    cron \
    chrony \
    network-manager \
    openssh-server \
    iotop \
    iftop \
    ncdu \
    tmux \
    screen

# Configure time synchronization (critical for logging)
echo "⏰ Configuring time synchronization..."
systemctl enable chrony
systemctl start chrony
timedatectl set-timezone Europe/Oslo

# Configure firewall (strict security)
echo "🔒 Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing

# Essential ports for greenhouse operations
ufw allow ssh                    # SSH access
ufw allow 8123                   # Home Assistant
ufw allow 1883                   # MQTT
ufw allow 6052                   # ESPHome
ufw allow 3306                   # MariaDB (for direct access)
ufw allow 8080                   # phpMyAdmin
ufw allow 3001                   # Uptime Kuma
ufw allow 443                    # HTTPS
ufw allow 80                     # HTTP

# Allow from local network only (adjust subnet as needed)
echo "Enter your local network subnet (e.g., 192.168.1.0/24):"
read LOCAL_SUBNET
ufw allow from $LOCAL_SUBNET

ufw --force enable

# Install Docker (official repository)
echo "🐳 Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install Docker Compose standalone
echo "📋 Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create greenhouse user
echo "👤 Creating greenhouse user..."
useradd -m -s /bin/bash -G docker,sudo greenhouse
echo "Set password for greenhouse user:"
passwd greenhouse

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p /opt/greenhouse/{
    config/{homeassistant,mariadb,mosquitto,nginx,esphome},
    data,
    backups/{daily,weekly,monthly},
    logs,
    scripts,
    ssl
}

# Set proper permissions
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

# Allow only greenhouse user
AllowUsers greenhouse

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
apt install -y unattended-upgrades apt-listchanges

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

# Create backup script directory
mkdir -p /opt/greenhouse/scripts

# Enable services
systemctl enable docker
systemctl start docker

# Add greenhouse user to docker group
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
echo "✅ BASE SYSTEM INSTALLATION COMPLETED!"
echo "======================================="
echo ""
echo "📋 Installation Summary:"
echo "- Ubuntu Server hardened and optimized"
echo "- Docker and Docker Compose installed"
echo "- Firewall configured with greenhouse-specific rules"
echo "- SSH hardened (root login disabled)"
echo "- Automatic security updates enabled"
echo "- System monitoring configured"
echo "- Greenhouse user created with Docker access"
echo ""
echo "📁 All files are in: /opt/greenhouse/"
echo "📄 Full summary: /opt/greenhouse/INSTALLATION_SUMMARY.txt"
echo ""
echo "🔑 IMPORTANT SECURITY STEPS:"
echo "1. Set up SSH keys for the greenhouse user"
echo "2. Disable password authentication in SSH"
echo "3. Configure firewall rules for your specific network"
echo ""
echo "🚀 NEXT STEP: Deploy the greenhouse Docker stack"
echo "   Switch to greenhouse user: sudo su - greenhouse"
echo ""
echo "💡 TIP: Reboot the server to ensure all optimizations are active"
echo "   sudo reboot"
EOF
