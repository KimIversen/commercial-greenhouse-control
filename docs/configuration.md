# Configuration Guide

## Environment Variables

All sensitive configuration is stored in the `.env` file at the project root. Required variables:

| Variable | Description |
|----------|-------------|
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |
| `MYSQL_HA_PASSWORD` | Home Assistant database user password |
| `TZ` | Timezone (default: `Europe/Oslo`) |
| `MQTT_PASSWORD` | MQTT broker password |
| `SMTP_SERVER` | SMTP server for email notifications |
| `SMTP_USERNAME` | SMTP login username |
| `SMTP_PASSWORD` | SMTP login password |
| `WATCHTOWER_EMAIL_FROM` | Sender address for Watchtower notifications |
| `WATCHTOWER_EMAIL_TO` | Recipient address for Watchtower notifications |

## ESPHome Secrets

ESPHome devices use a `secrets.yaml` file in the `esphome/` directory. Required entries:

```yaml
wifi_ssid: "your-wifi-ssid"
wifi_password: "your-wifi-password"
fallback_password: "fallback-ap-password"
api_encryption_key: "32-byte-base64-key"
ota_password: "ota-update-password"
mqtt_broker: "192.168.10.x"
mqtt_username: "greenhouse"
mqtt_password: "mqtt-password"
```

## Network Configuration

All ESP32 devices use static IPs on the `192.168.10.x` subnet:

| Device | IP Address |
|--------|-----------|
| Climate Sensor 1 (mains) | 192.168.10.150 |
| Soil Monitor 1 (battery) | 192.168.10.152 |
| Soil Monitor 2 (battery) | 192.168.10.153 |
| Soil Monitor 3 (battery) | 192.168.10.154 |
| Climate Sensor 3 (battery) | 192.168.10.155 |
| Valve Controller | 192.168.10.160 |
| Fan Controller | 192.168.10.170 |
| Fertigation Controller | 192.168.10.200 |

Gateway: `192.168.10.1` | Subnet: `255.255.255.0`

## Docker Services

Services are defined in `configs/docker-compose.yml` on a bridge network (`172.20.0.0/16`):

| Service | Port | Image |
|---------|------|-------|
| Home Assistant | 8123 | homeassistant/home-assistant:stable |
| MariaDB | 3306 | mariadb:10.11-jammy |
| ESPHome | 6052 | esphome/esphome:2024.12.4 |
| Mosquitto | 1883, 9001 | eclipse-mosquitto:2.0 |
| phpMyAdmin | 8080 | phpmyadmin/phpmyadmin:5.2 |
| Uptime Kuma | 3001 | louislam/uptime-kuma:1 |
| Node Exporter | 9100 | prom/node-exporter:v1.8.2 |
| Watchtower | - | containrrr/watchtower:1.7.1 |

## Database Configuration

MariaDB is tuned for a 32GB RAM server (`configs/mariadb/my.cnf`):
- InnoDB buffer pool: 8GB
- Log file size: 512MB
- Max connections: 200
- Binary logging enabled (ROW format, 7-day retention)
- Character set: UTF8MB4

Home Assistant recorder keeps 365 days of history with auto-purge.

## Battery Device Management

Battery-powered devices use deep sleep to conserve power. Key configuration:

- **OTA Mode**: Controlled via retained MQTT messages. When ON, device stays awake for firmware updates.
- **Deep Sleep**: Devices sleep between readings (15-30 minutes depending on device).
- **Low Battery**: Extended sleep is triggered when battery falls below 20%.

To update firmware on a battery device:
1. Run the `Wake for Update` script from the dashboard
2. Wait for the device to wake on its next cycle
3. Upload firmware via ESPHome dashboard
4. OTA mode auto-disables after the update

## Customization

### Soil Moisture Thresholds
Edit gauge thresholds in `configs/homeassistant/ui-lovelace.yaml`:
- Green: >45% VWC (optimal)
- Yellow: 35-45% VWC (needs attention)
- Red: <35% VWC (critical)

### Sensor Calibration
Calibration values are in each ESPHome device YAML under `calibrate_linear` filters.
Use the calibration tool at `esphome/soil-moisture-calibration/` to generate values for new sensors.

### Alert Configuration
- Battery alerts: `configs/homeassistant/automations.yaml`
- Email notifications: Configured via SMTP in `configuration.yaml`
- Threshold adjustments: Modify `numeric_state` triggers in automations
