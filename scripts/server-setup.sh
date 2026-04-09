#!/bin/bash
# Greenhouse Server Setup
# Run as root on fresh Ubuntu Server 22.04+ LTS
# This is the only OS-level script you need to run.

set -e

echo "GREENHOUSE SERVER SETUP"
echo "======================="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root: sudo ./server-setup.sh"
    exit 1
fi

# --- System packages ---
echo "[1/7] Updating system and installing packages..."
apt update && apt upgrade -y
apt install -y \
    curl wget git htop nano \
    ca-certificates gnupg lsb-release \
    fail2ban ufw \
    logrotate rsync cron chrony \
    openssh-server tmux

# --- Time ---
echo "[2/7] Configuring timezone..."
systemctl enable chrony
systemctl start chrony
timedatectl set-timezone Europe/Oslo

# --- Docker ---
echo "[3/7] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable docker
systemctl start docker

# --- Greenhouse user ---
echo "[4/7] Setting up greenhouse user..."
if ! id "greenhouse" &>/dev/null; then
    useradd -m -s /bin/bash -G docker,sudo greenhouse
    echo ""
    echo "Set password for the greenhouse user:"
    passwd greenhouse
else
    echo "User 'greenhouse' already exists"
    usermod -aG docker,sudo greenhouse
fi

# --- Directory structure ---
echo "[5/7] Creating directories..."
mkdir -p /opt/greenhouse/{config/{homeassistant,mariadb,mosquitto,esphome},backups,logs,scripts}
chown -R greenhouse:greenhouse /opt/greenhouse
chmod -R 755 /opt/greenhouse

# --- Firewall ---
echo "[6/7] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing

# Allow from local network (covers all 192.168.x.x)
ufw allow from 192.168.0.0/16

# Also allow SSH from anywhere (in case you connect from outside)
ufw allow ssh

ufw --force enable

# --- SSH config ---
# Keep it simple: password auth stays enabled, root login disabled.
# This means you can always recover by plugging in a keyboard and resetting the password.
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Remove any AllowUsers directive (don't lock yourself out)
sed -i '/^AllowUsers/d' /etc/ssh/sshd_config

systemctl restart ssh

# --- System optimizations ---
echo "[7/7] Applying system optimizations..."

# Only add if not already present
grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf || \
    echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf

grep -q "vm.swappiness" /etc/sysctl.conf || \
    cat >> /etc/sysctl.conf << 'EOF'

# Greenhouse optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p

# --- Auto-security updates ---
apt install -y unattended-upgrades
systemctl enable unattended-upgrades

# --- Done ---
echo ""
echo "========================================="
echo "SERVER SETUP COMPLETE"
echo "========================================="
echo ""
echo "User: greenhouse"
echo "Home: /home/greenhouse"
echo "Data: /opt/greenhouse/"
echo ""
echo "NEXT STEPS:"
echo "  1. From your Mac, copy your SSH key:"
echo "     ssh-copy-id greenhouse@$(hostname -I | awk '{print $1}')"
echo ""
echo "  2. Then deploy the greenhouse stack from your Mac:"
echo "     make deploy"
echo ""
echo "PASSWORD RECOVERY:"
echo "  If you forget the password, plug in a keyboard and monitor."
echo "  At the login prompt, switch to a TTY (Ctrl+Alt+F2),"
echo "  boot into recovery mode (hold Shift at GRUB), and run:"
echo "    passwd greenhouse"
echo ""
echo "  Password auth is intentionally left enabled so this always works."
echo ""
