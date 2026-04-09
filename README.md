# Commercial Greenhouse Control

Enterprise-grade IoT control system for commercial greenhouse operations with automated fertigation, climate control, and monitoring.

## Features

- **Soil Moisture Monitoring** - Calibrated capacitive sensors measuring Volumetric Water Content (VWC) across multiple zones
- **Climate Monitoring** - Dual DHT22 sensors for temperature and humidity with averaging
- **Automated Fertigation** - Venturi-based fertilizer injection with ratio monitoring and deviation alerts
- **Valve Control** - 9V latched solenoid valves via TB6612FNG motor drivers for zone irrigation
- **Fan Control** - PWM exhaust fans with emergency temperature override (35C)
- **Battery Management** - Deep sleep optimization, OTA mode control, discharge tracking, and low-battery alerts
- **Tank Level Monitoring** - Ultrasonic sensors for water and fertilizer tank levels
- **Dashboard** - Lovelace YAML dashboard with gauges, trends, and device management controls

## Architecture

```
ESP32 Devices  -->  MQTT (Mosquitto)  -->  Home Assistant  -->  MariaDB
                                               |
                                          Automations & Alerts
```

- **9 ESP32 devices** (soil monitors, climate sensors, valve/fan/fertigation controllers)
- **8 Docker services** (Home Assistant, MariaDB, ESPHome, Mosquitto, phpMyAdmin, Uptime Kuma, Node Exporter, Watchtower)
- Battery-powered devices use deep sleep with 15-30 minute cycles

## Hardware

- ESP32-C3 (XIAO) and ESP32-S3 development boards
- Capacitive soil moisture sensors with piecewise linear calibration
- DHT22 temperature/humidity sensors
- DS18B20 soil temperature probes
- JSN-SR04T ultrasonic tank level sensors
- 9V latched solenoid valves with TB6612FNG H-bridge drivers
- Venturi fertilizer injection system

## Quick Start

1. **Deploy infrastructure:**
   ```bash
   sudo bash scripts/deploy-greenhouse.sh
   ```

2. **Flash ESP32 devices:**
   - Access ESPHome dashboard at `http://server-ip:6052`
   - Configure `esphome/secrets.yaml` with WiFi/MQTT credentials
   - Compile and upload device firmware

3. **Configure Home Assistant:**
   - Access at `http://server-ip:8123`
   - Verify MQTT sensors appear in Developer Tools > States

4. **Ongoing management:**
   ```bash
   make help          # View all commands
   make status        # Check system status
   make update        # Update configs and restart
   make health        # System health check
   make backup        # Manual backup
   ```

## Documentation

- [Configuration Guide](docs/configuration.md) - Environment setup, network config, customization
- [Installation Guide](docs/installation-guide.md) - Detailed deployment instructions
- [Battery Setup](BATTERY_SETUP.md) - Battery-powered device configuration

## Project Structure

```
configs/
  docker-compose.yml          # All Docker service definitions
  homeassistant/              # Home Assistant configuration
    configuration.yaml        # Main HA config
    automations.yaml          # Battery alerts, system triggers
    mqtt.yaml                 # 80+ MQTT sensor definitions
    scripts.yaml              # Battery management scripts
    ui-lovelace.yaml          # Dashboard (5 views)
    sensors/                  # Template sensors, system sensors, input helpers
  mariadb/my.cnf              # Database tuning (32GB RAM)

esphome/                      # ESP32 device firmware configs
  greenhouse-soil-*-battery.yaml   # Battery soil monitors (3 variants)
  greenhouse-climate-*.yaml        # Climate sensors (mains + battery)
  fertigation-control-system.yaml  # Fertigation controller
  valve-controller.yaml            # Irrigation valve control
  fan-controller.yaml              # Exhaust fan control

scripts/
  deploy-greenhouse.sh        # Full system deployment
  backup.sh                   # Automated backup with Google Drive
  system-monitor.sh           # Health monitoring with email alerts
```

## License

See [LICENSE](LICENSE) for details.
