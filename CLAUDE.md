# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## System Overview

This is a commercial greenhouse control system built around Home Assistant with ESPHome devices. The system manages:
- Automated fertigation (fertilizer + irrigation) with precise ratio monitoring
- Soil moisture monitoring with calibrated capacitive sensors  
- Climate control and environmental monitoring
- Tank level monitoring with ultrasonic sensors
- Data logging via MariaDB and MQTT

## Architecture

### Core Components
- **Home Assistant**: Central control system (Docker container on port 8123)
- **MariaDB**: Database for sensor data and automation history (port 3306)
- **MQTT (Mosquitto)**: Message broker for ESP32 device communication (port 1883)
- **ESPHome**: Manages ESP32 firmware and OTA updates (port 6052)
- **phpMyAdmin**: Database management interface (port 8080)
- **Uptime Kuma**: Service monitoring (port 3001)

### ESP32 Device Types
1. **Soil Sensor Nodes**: Monitor soil VWC (Volumetric Water Content) using calibrated capacitive sensors
2. **Fertigation Controller**: Manages water/fertilizer mixing with venturi system and ratio monitoring
3. **Valve Controllers**: Control irrigation zones and water distribution
4. **Fan Controllers**: Manage greenhouse ventilation

### Data Flow
1. ESP32 devices collect sensor data
2. Data published via MQTT to Home Assistant
3. Home Assistant processes data and triggers automations
4. Control commands sent back to ESP32 devices
5. All data logged to MariaDB for historical analysis

## Development Commands

### System Management (via Makefile)
```bash
# View all available commands
make help

# Update entire system (configs + restart)
make update

# Update configuration files only
make update-configs

# Restart all Docker services
make restart-all

# Check system status
make status

# View service logs
make logs
make logs SERVICE=homeassistant  # specific service

# System health check
make health

# Manual backup
make backup

# Environment info
make env-info
```

### Docker Operations
```bash
# View running containers
docker-compose ps

# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f [service_name]

# Restart specific service
docker-compose restart [service_name]
```

### ESPHome Device Management
```bash
# Access ESPHome dashboard at http://localhost:6052

# Compile firmware (from esphome/ directory)
esphome compile soil-sensor-node.yaml

# Upload via OTA (device must be online)
esphome upload soil-sensor-node.yaml

# View device logs
esphome logs soil-sensor-node.yaml
```

## Key Configuration Files

### Docker & Infrastructure
- `configs/docker-compose.yml`: All service definitions and networking
- `configs/homeassistant/configuration.yaml`: Home Assistant setup and integrations
- `configs/mariadb/my.cnf`: Database optimization settings

### ESPHome Device Configurations
- `esphome/soil-sensor-node.yaml`: Soil moisture monitoring with calibrated VWC sensors
- `esphome/fertigation-control-system.yaml`: Advanced fertigation controller with ratio monitoring
- `esphome/valve-controller.yaml`: Irrigation zone valve control
- `esphome/fan-controller.yaml`: Ventilation management

### Scripts
- `scripts/backup.sh`: Automated backup system
- `scripts/system-monitor.sh`: System health monitoring
- `scripts/deploy-greenhouse.sh`: Full system deployment

### Lovelace Dashboard
- `configs/homeassistant/ui-lovelace.yaml`: Main dashboard configuration in YAML mode

## Important Development Notes

### Sensor Calibration
- Soil moisture sensors require individual calibration
- Calibration data is embedded in ESPHome YAML files as piecewise linear interpolation
- Never modify calibration values without proper soil testing

### Safety Systems
- All valves default to CLOSED state on power loss
- Emergency stop functionality closes all valves immediately
- Ratio monitoring prevents incorrect fertilizer concentrations
- Low tank level alerts prevent system damage

### MQTT Topic Structure
```
greenhouse/
├── soil1/           # Soil sensor node 1
│   ├── sensor1_vwc
│   ├── sensor2_vwc
│   └── average_vwc
├── fertigation/     # Fertigation controller
│   ├── tank_levels
│   ├── flow_rates
│   └── mixing_complete
└── climate1/        # Climate sensors
    ├── temperature
    └── humidity
```

### Database Schema
- Home Assistant uses `homeassistant` database
- Sensor data stored in `states` table
- Historical data retention: 365 days (configurable)

## Environment Requirements

### Network Configuration
- Static IP addresses for all ESP32 devices (192.168.10.x range)
- MQTT broker accessible on local network
- Home Assistant accessible via web interface

### Hardware Dependencies
- ESP32-C3 or ESP32-S3 development boards
- Capacitive soil moisture sensors (calibrated)
- JSN-SR04T ultrasonic level sensors
- 9V latched solenoid valves controlled via TB6612FNG motor drivers
- Venturi fertilizer injection system

## Valve Control System

### Latched Solenoid Valves
- Uses 9V latched solenoid valves that maintain position without power
- Controlled via TB6612FNG motor driver modules
- Requires directional pulse to switch between OPEN and CLOSE positions
- Each valve needs two control signals: direction and enable pulse

### TB6612FNG Wiring Pattern
```
ESP32 GPIO -> TB6612FNG
AIN1/BIN1   -> Direction control (HIGH=open, LOW=close)
AIN2/BIN2   -> Inverted direction (!AIN1/!BIN1)
PWMA/PWMB   -> Enable pulse (short pulse to actuate)
```

## Standard Microcontroller Components

### Required Components for All ESP32 Devices
Every ESP32 device in the system must include these standard components for monitoring and diagnostics:

#### Connectivity & Status Monitoring
```yaml
# WiFi signal strength monitoring
sensor:
  - platform: wifi_signal
    name: "WiFi Signal"
    id: wifi_signal_sensor
    update_interval: 60s
    unit_of_measurement: "dBm"
    device_class: signal_strength
    entity_category: diagnostic

# System uptime tracking
  - platform: uptime
    name: "Uptime"
    id: uptime_sensor
    device_class: duration
    entity_category: diagnostic

# Device connectivity status
binary_sensor:
  - platform: status
    name: "Device Status"
    id: device_status
    device_class: connectivity

# Device online/offline status via MQTT
mqtt:
  birth_message:
    topic: greenhouse/[device_name]/status
    payload: online
    retain: true
  will_message:
    topic: greenhouse/[device_name]/status
    payload: offline
    retain: true
```

#### Battery Monitoring (for battery-powered devices)
```yaml
# Battery voltage and percentage
sensor:
  - platform: adc
    pin: A0  # or appropriate battery monitoring pin
    name: "Battery Voltage"
    id: battery_voltage
    attenuation: 11dB
    filters:
      - multiply: 2.0  # Adjust based on voltage divider
    update_interval: 300s  # 5 minutes
    accuracy_decimals: 2
    unit_of_measurement: "V"
    device_class: voltage
    entity_category: diagnostic

  - platform: template
    name: "Battery Level"
    id: battery_level
    lambda: |-
      float voltage = id(battery_voltage).state;
      // Li-ion: 4.2V = 100%, 3.0V = 0%
      if (voltage >= 4.2) return 100.0;
      if (voltage <= 3.0) return 0.0;
      return ((voltage - 3.0) / 1.2) * 100.0;
    update_interval: 300s
    unit_of_measurement: "%"
    device_class: battery
    accuracy_decimals: 0

# Low battery alert
binary_sensor:
  - platform: template
    name: "Low Battery Alert"
    id: low_battery_alert
    lambda: 'return id(battery_level).state < 20;'
    device_class: battery_low
```

#### System Health & Diagnostics
```yaml
# Free heap memory monitoring
sensor:
  - platform: template
    name: "Free Heap"
    id: free_heap
    lambda: 'return heap_caps_get_free_size(MALLOC_CAP_INTERNAL);'
    update_interval: 60s
    unit_of_measurement: "bytes"
    entity_category: diagnostic
    accuracy_decimals: 0

# Boot counter for reliability tracking
  - platform: template
    name: "Boot Counter"
    id: boot_counter
    lambda: |-
      static uint32_t boot_count = 0;
      boot_count++;
      return boot_count;
    update_interval: never
    entity_category: diagnostic

# Reset reason tracking
text_sensor:
  - platform: template
    name: "Last Reset Reason"
    id: reset_reason
    lambda: |-
      switch (esp_reset_reason()) {
        case ESP_RST_POWERON: return {"Power On"};
        case ESP_RST_EXT: return {"External Reset"};
        case ESP_RST_SW: return {"Software Reset"};
        case ESP_RST_PANIC: return {"Exception/Panic"};
        case ESP_RST_INT_WDT: return {"Interrupt Watchdog"};
        case ESP_RST_TASK_WDT: return {"Task Watchdog"};
        case ESP_RST_WDT: return {"Other Watchdog"};
        case ESP_RST_DEEPSLEEP: return {"Deep Sleep Wake"};
        case ESP_RST_BROWNOUT: return {"Brownout Reset"};
        case ESP_RST_SDIO: return {"SDIO Reset"};
        default: return {"Unknown"};
      }
    entity_category: diagnostic
```

#### Standard Control & Maintenance
```yaml
# Manual restart button
button:
  - platform: restart
    name: "Restart Device"
    id: restart_button
    entity_category: config

# Safe mode switch for troubleshooting
switch:
  - platform: safe_mode
    name: "Safe Mode"
    id: safe_mode_switch
    entity_category: config

# Status LED for visual feedback
status_led:
  pin:
    number: GPIO2  # Built-in LED on most ESP32 boards
    inverted: true

# OTA mode switch for firmware updates
switch:
  - platform: template
    name: "OTA Mode"
    id: ota_mode
    icon: mdi:upload-network
    entity_category: config
    turn_on_action:
      - logger.log: "OTA mode enabled - ready for firmware update"
    turn_off_action:
      - logger.log: "OTA mode disabled"
```

#### Time Synchronization & Scheduling
```yaml
# Network time synchronization
time:
  - platform: sntp
    id: sntp_time
    timezone: "Europe/Oslo"
    servers:
      - pool.ntp.org
      - time.google.com
    on_time_sync:
      then:
        - logger.log: "Time synchronized"

# Time-based sensors
sensor:
  - platform: template
    name: "Hours Since Boot"
    lambda: 'return id(uptime_sensor).state / 3600.0;'
    update_interval: 300s
    unit_of_measurement: "h"
    accuracy_decimals: 1
    entity_category: diagnostic
```

#### Environmental Monitoring (for applicable devices)
```yaml
# Internal temperature monitoring (ESP32 built-in sensor)
sensor:
  - platform: internal_temperature
    name: "Device Temperature"
    id: device_temperature
    update_interval: 60s
    entity_category: diagnostic

# Temperature-based alerts
binary_sensor:
  - platform: template
    name: "Device Overheating"
    lambda: 'return id(device_temperature).state > 70.0;'
    device_class: heat
```

#### Data Logging & Debugging
```yaml
# Periodic status reporting via MQTT
interval:
  - interval: 300s  # Every 5 minutes
    then:
      - mqtt.publish:
          topic: greenhouse/[device_name]/diagnostics
          payload: !lambda |-
            char buffer[400];
            sprintf(buffer, 
              "{\"uptime\":%d,\"wifi_rssi\":%.0f,\"free_heap\":%d,\"temperature\":%.1f,\"battery\":%.1f}",
              (int)id(uptime_sensor).state,
              id(wifi_signal_sensor).state,
              (int)id(free_heap).state,
              id(device_temperature).state,
              id(battery_level).state  // Remove if not battery powered
            );
            return std::string(buffer);
          retain: false

# Debug logging configuration
logger:
  level: INFO
  logs:
    sensor: WARN
    mqtt: INFO
    wifi: INFO
    api: WARN
    ota: INFO
```

### Implementation Guidelines

#### Device Naming Convention
- Use consistent naming: `greenhouse-[type]-[number]` (e.g., `greenhouse-soil-01`, `greenhouse-valve-02`)
- All sensor names should include device identifier for uniqueness

#### Power Management
- Battery-powered devices should use deep sleep between readings
- Implement progressive sleep intervals during low battery conditions
- Solar-powered devices should monitor charging status

#### Error Handling & Recovery
- Implement automatic reconnection for WiFi and MQTT
- Use exponential backoff for failed connections
- Log all errors with timestamps for debugging

#### Performance Optimization
- Use appropriate update intervals (avoid unnecessary frequent updates)
- Implement sensor filtering to reduce noise
- Use internal sensors sparingly to avoid memory issues

## Troubleshooting

### Common Issues
1. **ESP32 not connecting**: Check WiFi credentials in secrets
2. **Sensor readings erratic**: Verify power supply stability and sensor wiring
3. **MQTT messages not received**: Check broker credentials and network connectivity
4. **Database connection errors**: Verify MariaDB container status and credentials
5. **Valves not switching**: Check TB6612FNG power supply and GPIO connections

### Log Locations
- Home Assistant: `docker-compose logs homeassistant`
- System logs: `logs/` directory
- ESPHome device logs: via ESPHome dashboard or CLI

### Recovery Procedures
- Emergency stop: `make restart-all` or physical power cycle
- Database recovery: Restore from `backups/` directory
- Configuration reset: Re-run `scripts/deploy-greenhouse.sh`

## Lovelace Dashboard Configuration

### Dashboard Structure
The system uses Lovelace in YAML mode with 6 main views:

1. **Overview**: System status summary and quick actions
2. **Climate**: Temperature and humidity monitoring with trends
3. **Soil Moisture**: VWC monitoring per zone with individual sensor details
4. **Fertigation**: Tank levels, valve controls, and flow monitoring
5. **System Health**: Device connectivity and system resources
6. **History**: Long-term trends (7-14 days) for all sensors

### Custom Components Used
- **mini-graph-card**: For trend visualization and historical data
- **button-card**: For enhanced control interfaces
- Install via HACS or add manually to `/config/www/`

### Dashboard Features
- **Real-time gauges**: Visual tank levels, moisture percentages, temperature ranges
- **Color-coded alerts**: Green/yellow/red thresholds for critical parameters
- **Trend analysis**: Multiple time ranges (24h, 7d, 14d) for different data types
- **Device diagnostics**: WiFi signal strength, connectivity status, system health
- **Manual controls**: Valve operation, OTA mode switches, system restarts

### Gauge Thresholds
```yaml
# Soil Moisture (VWC %)
severity:
  green: 45    # Optimal range
  yellow: 35   # Needs attention
  red: 25      # Critical low

# Tank Levels (%)
severity:
  green: 40    # Good levels
  yellow: 20   # Low warning
  red: 10      # Critical refill needed

# Temperature (°C)
severity:
  green: 18    # Optimal range
  yellow: 25   # Getting warm
  red: 30      # Too hot
```

### Customization Guidelines
- Modify thresholds in `ui-lovelace.yaml` based on crop requirements
- Add new sensor entities to appropriate views
- Update time ranges (`hours_to_show`) based on monitoring needs
- Color themes can be customized per chart using `color_thresholds`

## Security Considerations

- All ESP32 devices use encrypted API keys
- OTA updates protected with passwords
- Database access restricted to local network
- Email notifications for critical alerts
- Firewall rules configured via installation script