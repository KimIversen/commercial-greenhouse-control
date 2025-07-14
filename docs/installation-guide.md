# 🏭 Commercial Greenhouse Server Installation Checklist

## **Prerequisites**
- [ ] AMD Ryzen server with 32GB RAM ready
- [ ] Fresh Ubuntu Server 22.04 LTS installed
- [ ] Network connection configured
- [ ] Root access available

---

## **Phase 1: Base System Setup (Run as root)**

### Step 1: Download and Run Base Installation
```bash
# Download the server setup script
wget -O greenhouse-server-setup.sh [script-url]
chmod +x greenhouse-server-setup.sh

# Run as root
sudo ./greenhouse-server-setup.sh
```

### Step 2: Configure Network Settings
- [ ] Set static IP address for the server
- [ ] Configure DNS settings
- [ ] Test internet connectivity
- [ ] Note your local network subnet (e.g., 192.168.1.0/24)

### Step 3: Security Configuration
- [ ] Script configures firewall automatically
- [ ] SSH hardening applied
- [ ] Fail2ban installed and configured
- [ ] Automatic security updates enabled

### Step 4: Reboot System
```bash
sudo reboot
```

---

## **Phase 2: Greenhouse Stack Deployment (Run as greenhouse user)**

### Step 1: Switch to Greenhouse User
```bash
sudo su - greenhouse
cd /opt/greenhouse
```

### Step 2: Download and Run Deployment Script
```bash
# Download the deployment script
wget -O deploy-greenhouse.sh [script-url]
chmod +x deploy-greenhouse.sh

# Run deployment
./deploy-greenhouse.sh
```

### Step 3: SSH Key Setup
- [ ] SSH keys generated automatically
- [ ] Copy public key to your management machines
- [ ] Test SSH key authentication
- [ ] Disable password authentication (optional)

### Step 4: Email Configuration
Edit the secrets file with your email settings:
```bash
nano config/homeassistant/secrets.yaml
```

Update these fields:
- [ ] `smtp_server`: Your SMTP server
- [ ] `smtp_username`: Your email username  
- [ ] `smtp_password`: Your email app password
- [ ] `admin_email`: Where to send alerts

### Step 5: Restart Home Assistant
```bash
docker-compose restart homeassistant
```

---

## **Phase 3: Initial Configuration**

### Step 1: Access Home Assistant
- [ ] Open http://YOUR-SERVER-IP:8123
- [ ] Complete initial user setup
- [ ] Create admin account
- [ ] Skip integrations for now

### Step 2: Access ESPHome Dashboard
- [ ] Open http://YOUR-SERVER-IP:6052
- [ ] Verify ESPHome is accessible
- [ ] Ready for adding ESP32 devices

### Step 3: Database Access
- [ ] Open http://YOUR-SERVER-IP:8080 (phpMyAdmin)
- [ ] Login with MariaDB root credentials (from .env file)
- [ ] Verify database connectivity

### Step 4: System Monitoring
- [ ] Open http://YOUR-SERVER-IP:3001 (Uptime Kuma)
- [ ] Complete initial setup
- [ ] Add monitoring for critical services

---

## **Phase 4: Testing & Validation**

### Step 1: Test Backup System
```bash
./scripts/backup.sh
ls -la backups/daily/
```

### Step 2: Test System Monitoring
```bash
./scripts/system-monitor.sh
tail -f logs/system-monitor.log
```

### Step 3: Test Container Health
```bash
docker-compose ps
docker-compose logs homeassistant
```

### Step 4: Test Alert System
- [ ] Configure email in Home Assistant
- [ ] Send test notification
- [ ] Verify email delivery

---

## **Phase 5: Security Hardening**

### Step 1: SSH Security
```bash
# Edit SSH config to disable password auth (optional)
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

### Step 2: Firewall Review
```bash
sudo ufw status verbose
# Verify only necessary ports are open
```

### Step 3: Update Default Passwords
- [ ] Change MariaDB passwords if needed
- [ ] Update MQTT passwords
- [ ] Review all credentials in .env file

---

## **Phase 6: ESP32 Device Preparation**

### Step 1: Prepare ESPHome Configurations
- [ ] Create sensor node configurations
- [ ] Create valve controller configuration  
- [ ] Create fan controller configurations

### Step 2: Test ESP32 Programming
- [ ] Connect one ESP32 via USB
- [ ] Flash test firmware via ESPHome
- [ ] Verify OTA updates work

---

## **Success Criteria Checklist**

### System Health
- [ ] All Docker containers running and healthy
- [ ] Database accessible and responding
- [ ] Home Assistant web interface accessible
- [ ] ESPHome dashboard accessible
- [ ] System monitoring active

### Security
- [ ] Firewall configured and active
- [ ] SSH access secured with keys
- [ ] All services using strong passwords
- [ ] Fail2ban active and monitoring

### Backup & Recovery
- [ ] Automated backups working
- [ ] Backup restoration tested
- [ ] System monitoring alerts configured
- [ ] Email notifications working

### Remote Access
- [ ] SSH access from management machines
- [ ] Web interfaces accessible from network
- [ ] Mobile access tested (if required)
- [ ] VPN setup (if required)

---

## **Important Files & Locations**

```
/opt/greenhouse/
├── .env                          # All passwords and secrets
├── docker-compose.yml            # Service definitions
├── config/
│   ├── homeassistant/           # HA configuration
│   ├── mariadb/                 # Database config
│   └── mosquitto/               # MQTT config
├── backups/                     # Automated backups
├── logs/                        # System logs
└── scripts/                     # Maintenance scripts
```

---

## **Emergency Information**

### Critical Commands
```bash
# View all service status
docker-compose ps

# Restart all services
docker-compose restart

# Stop everything
docker-compose down

# Start everything
docker-compose up -d

# View service logs
docker-compose logs -f [service_name]
```

### Emergency Access
- **SSH**: Port 22 (key authentication only)
- **Home Assistant**: Port 8123
- **Database**: Port 3306
- **MQTT**: Port 1883

### Support Contacts
- [ ] Document technical contact information
- [ ] Emergency procedures documented
- [ ] Backup administrator access configured

---

## **Post-Installation Notes**

**Record the following information:**
- [ ] Server IP address: _______________
- [ ] SSH key location: _______________
- [ ] Database root password: _______________
- [ ] Home Assistant admin: _______________
- [ ] Email configuration: _______________

**Installation completed by:** _______________
**Date:** _______________
**System validated by:** _______________
