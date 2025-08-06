# Battery-Powered Soil Monitor Setup Guide

## Hardware Changes Summary
- **Removed**: 1 soil moisture sensor (was on GPIO4)
- **Added**: Battery voltage monitoring on GPIO4 (with 220kΩ voltage divider)
- **Added**: 2x DS18B20 temperature sensors on GPIO5
- **Added**: 2x DHT22 sensors on GPIO6 and GPIO7
- **Power**: Now battery-powered with deep sleep capability

## Configuration Files Created
1. **ESPHome Config**: `esphome/greenhouse-soil-2-battery.yaml`
2. **HA Automations**: `configs/homeassistant/automations/soil-monitor-battery.yaml`
3. **Lovelace Card**: `configs/homeassistant/lovelace/battery-monitor-card.yaml`

## Key Features

### Deep Sleep Operation
- **Sleep Duration**: 15 minutes
- **Awake Duration**: 25 seconds (20s for readings + 5s buffer)
- **Reading Frequency**: 1 reading per second while awake (20 total readings)
- **Data Averaging**: All 20 readings are averaged before transmission

### OTA Mode Control
- **Default State**: ON (to allow initial connection and setup)
- **Auto-disable**: Turns OFF automatically 2 minutes after device connects
- **Manual Control**: Can be toggled from Home Assistant
- **Behavior**: When ON, device stays awake; when OFF, enters deep sleep cycle

### Battery Monitoring
- **Voltage Range**: 3.0V (0%) to 4.2V (100%) for Li-ion batteries
- **Alerts**: 
  - Low battery warning at 20%
  - Critical battery alert at 10%
- **Voltage Divider**: 220kΩ resistors provide 2:1 ratio

## Deployment Steps

### 1. Update DS18B20 Addresses
First, flash the device to discover the DS18B20 addresses:

```bash
# From the esphome directory
esphome run greenhouse-soil-2-battery.yaml
```

Look in the logs for lines like:
```
Found Dallas sensor with address: 0x2800000000000000
Found Dallas sensor with address: 0x2800000000000001
```

Update the configuration with actual addresses:
```yaml
- platform: dallas
  address: 0x2800000000000000  # Replace with your actual address
  name: "Soil Temperature 1"
```

### 2. Flash the Device
```bash
# Compile and upload
esphome run greenhouse-soil-2-battery.yaml

# Or just compile
esphome compile greenhouse-soil-2-battery.yaml
```

### 3. Add Automations to Home Assistant
Add the automations file to your configuration.yaml:
```yaml
automation: !include_dir_merge_list automations/
```

Or manually copy the automations to your existing automation file.

### 4. Add Lovelace Card
1. Open Home Assistant UI
2. Edit Dashboard
3. Add Manual Card
4. Paste the contents of `battery-monitor-card.yaml`

### 5. Initial Setup Sequence
1. **Power on device** with charged battery
2. **Device connects** with OTA mode ON (default)
3. **Wait for connection** in Home Assistant (check Developer Tools > States)
4. **OTA mode auto-disables** after 2 minutes
5. **Device enters deep sleep** cycle

## Manual Controls in Home Assistant

### Wake Device for Updates
```yaml
service: switch.turn_on
target:
  entity_id: switch.greenhouse_soil_monitor_2_ota_mode
```

### Force Sleep
```yaml
service: button.press
target:
  entity_id: button.greenhouse_soil_monitor_2_force_sleep
```

### Mark Battery as Charged
```yaml
service: script.soil_monitor_2_mark_battery_charged
```

## Power Consumption Estimates

### Active Mode (OTA ON)
- WiFi connected: ~80-120mA
- Sensors active: ~20mA
- Total: ~100-140mA continuous

### Deep Sleep Mode
- ESP32-C3 deep sleep: ~5μA
- Voltage divider leak: ~9μA (3.7V / 440kΩ)
- Total sleep current: ~15μA

### Battery Life Calculation
With 2000mAh battery:
- Active time per day: (24h × 60min / 15min) × 25s = 40 minutes
- Active consumption: 40min × 120mA = 80mAh
- Sleep consumption: 23.3h × 0.015mA = 0.35mAh
- **Daily total**: ~80.35mAh
- **Estimated battery life**: 2000mAh / 80.35mAh = **~25 days**

## Troubleshooting

### Device Not Entering Sleep
- Check OTA mode is OFF in Home Assistant
- Verify no active OTA update in progress
- Check logs: `esphome logs greenhouse-soil-2-battery.yaml`

### Device Not Waking Up
- Battery may be depleted (check last known level)
- WiFi connection issues (check router)
- Increase sleep duration temporarily for debugging

### Incorrect Battery Readings
- Verify voltage divider ratio (should be 2:1)
- Adjust multiplier in config if needed:
  ```yaml
  filters:
    - multiply: 2.0  # Adjust this value
  ```

### DS18B20 Not Found
- Check wiring (3.3V, GND, and 4.7kΩ pullup on data line)
- Verify GPIO5 connection
- Use discovery mode first to find addresses

### DHT22 Reading Errors
- Ensure proper power supply (3.3V)
- Check pull-up resistor on data line (10kΩ recommended)
- Increase reading interval if getting frequent errors

## MQTT Topics

### Published Data
- `greenhouse/soil2/status` - Online/offline status
- `greenhouse/soil2/sensor1_vwc` - Soil moisture sensor 1
- `greenhouse/soil2/sensor2_vwc` - Soil moisture sensor 2
- `greenhouse/soil2/average_vwc` - Average soil moisture
- `greenhouse/soil2/soil_temp_1` - Soil temperature 1
- `greenhouse/soil2/soil_temp_2` - Soil temperature 2
- `greenhouse/soil2/air_temp_1` - Air temperature 1
- `greenhouse/soil2/air_temp_2` - Air temperature 2
- `greenhouse/soil2/air_humidity_1` - Air humidity 1
- `greenhouse/soil2/air_humidity_2` - Air humidity 2
- `greenhouse/soil2/battery_voltage` - Battery voltage
- `greenhouse/soil2/battery_level` - Battery percentage
- `greenhouse/soil2/averaged_data` - JSON with all averaged readings
- `greenhouse/soil2/diagnostics` - Device health metrics

### Control Topics
- `greenhouse/soil2/ota_mode` - Send "ON" or "OFF" to control OTA mode

## Home Assistant Entities

### Sensors
- `sensor.greenhouse_soil_monitor_2_soil_vwc_sensor_1`
- `sensor.greenhouse_soil_monitor_2_soil_vwc_sensor_2`
- `sensor.greenhouse_soil_monitor_2_average_soil_vwc`
- `sensor.greenhouse_soil_monitor_2_soil_temperature_1`
- `sensor.greenhouse_soil_monitor_2_soil_temperature_2`
- `sensor.greenhouse_soil_monitor_2_air_temperature_1`
- `sensor.greenhouse_soil_monitor_2_air_temperature_2`
- `sensor.greenhouse_soil_monitor_2_air_humidity_1`
- `sensor.greenhouse_soil_monitor_2_air_humidity_2`
- `sensor.greenhouse_soil_monitor_2_battery_voltage`
- `sensor.greenhouse_soil_monitor_2_battery_level`
- `sensor.greenhouse_soil_monitor_2_wifi_signal`
- `sensor.greenhouse_soil_monitor_2_device_temperature`

### Binary Sensors
- `binary_sensor.greenhouse_soil_monitor_2_device_status`
- `binary_sensor.greenhouse_soil_monitor_2_low_battery_alert`
- `binary_sensor.greenhouse_soil_monitor_2_device_overheating`

### Switches
- `switch.greenhouse_soil_monitor_2_ota_mode`
- `switch.greenhouse_soil_monitor_2_safe_mode`

### Buttons
- `button.greenhouse_soil_monitor_2_restart_device`
- `button.greenhouse_soil_monitor_2_force_sleep`

## Notes

### Battery Selection
- Recommended: 18650 Li-ion cell (2000-3000mAh)
- Alternative: LiPo battery with protection circuit
- Ensure battery protection circuit for safety

### Solar Charging (Optional)
For solar charging, add:
- 6V solar panel (2-5W)
- TP4056 charging module with protection
- Connect to battery in parallel with load

### Calibration Preservation
The soil moisture calibration values from your original configuration have been preserved:
- Sensor 1: 1345→51%, 1396→45%, 1556→30%, 3408→0%
- Sensor 2: 1381→51%, 1454→45%, 1881→30%, 3457→0%

These values are specific to your sensors and soil type - do not modify without recalibration.