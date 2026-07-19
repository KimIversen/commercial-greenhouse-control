# TX-E Tensiometer ESPHome Node — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. This is ESPHome firmware + HA dashboard config, **not** unit-tested code — each task's "test" is an `esphome config`/`compile` pass (or a `yaml.safe_load` check) **plus observing real values** in the ESPHome web server / HA, exactly like the greenhouse-metrics plan. **LIVE COMMERCIAL greenhouse** — validate before flashing/reloading; some steps are physical and marked **[Human]**.

**Goal:** Stand up a dedicated ESP32-S3 node that reads 2× MMM tech TX-E tensiometers and publishes soil-water-tension (kPa) + a zone average to Home Assistant, then start a 1–2 week baseline log.

**Architecture:** One self-contained ESPHome config (`esphome/greenhouse-tensiometer.yaml`) reads two ADC1 pins (each fed by a 10 k/10 k divider), converts pin volts → kPa with a `calibrate_linear` filter encoding the TX-E's **inverted** transfer function, and exposes the entities over the native HA API. A dashboard card on the existing Metrics view visualises the dryback. **No irrigation automation** — that stays parked.

**Tech Stack:** ESPHome (arduino framework, ESP32-S3), flashed from the Mac via `uvx esphome`; Home Assistant 2026.x YAML dashboard deployed by rsync to `greenhouse:/opt/greenhouse/config/homeassistant/`.

## Global Constraints

- **Source of truth:** `docs/superpowers/specs/2026-07-04-tensiometer-esphome-design.md`.
- **TX-E transfer function (verbatim, INVERTED):** `4.50 V = 0 kPa (wet)`, `0.50 V = 100 kPa (dry)`, linear, 40 mV/kPa. Supply **5.0 VDC — never exceed** (ratiometric). Wiring: **RED=+5 V, BLACK=GND, WHITE=signal**.
- **Divider (verbatim):** 10 kΩ top (WHITE→pin) + 10 kΩ bottom (pin→GND), ratio 0.5 → pin `2.25 V (0 kPa)`…`0.25 V (100 kPa)`. Calibration: `calibrate_linear: [2.25 -> 0.0, 0.25 -> 100.0]`, clamp 0–100 kPa.
- **Pins (verbatim):** Sensor 1 → **GPIO1** (ADC1_CH0), Sensor 2 → **GPIO2** (ADC1_CH1). Non-strapping, ADC1 (WiFi-safe). ADC2 forbidden.
- **Node:** `board: esp32-s3-devkitc-1`, `flash_size: 16MB`, arduino. Static IP **192.168.10.161**. First flash over USB `/dev/cu.usbmodem2101`; OTA after.
- **Comms:** native API only (no MQTT). **Entity ids** derive as `sensor.greenhouse_tensiometer_*` (device name prefix) — this supersedes the spec's tentative `gh_*` note (the spec deferred exact slugs to this plan).
- **Common ground is mandatory** (sensor BLACK + divider bottom + ESP GND + 5 V-supply GND all tied).
- **No changes to `automations.yaml`.** Deploy/commit **named files only**; branch `greenhouse-automation-2026-06-28` is current; commit only when the work of a task is validated.
- **ESPHome CLI:** global `esphome` is broken — use `uvx esphome`; run from the `esphome/` dir so `secrets.yaml` resolves. Reused secrets: `api_encryption_key`, `ota_password`, `wifi_ssid`, `wifi_password`, `fallback_password`.
- **Known deploy-time confirm:** WiFi SSID — the `Hi-Wifi`/`HiWiFi` gotcha. Default uses `wifi_ssid`/`wifi_password` (like the valve controller); if the node can't join, switch to `hiwifi_ssid`/`hiwifi_password` (like climate-2).

---

## Task 1: ESPHome node config (`greenhouse-tensiometer.yaml`)

**Files:**
- Create: `esphome/greenhouse-tensiometer.yaml`

**Interfaces:**
- Produces (HA entities via native API): `sensor.greenhouse_tensiometer_1_kpa`, `sensor.greenhouse_tensiometer_2_kpa`, `sensor.greenhouse_tensiometer_average_kpa`, `sensor.greenhouse_tensiometer_1_volts`, `sensor.greenhouse_tensiometer_2_volts`, `binary_sensor.greenhouse_tensiometer_1_check_prime`, `binary_sensor.greenhouse_tensiometer_2_check_prime`, `binary_sensor.greenhouse_tensiometer_status`, plus WiFi/uptime diagnostics.

- [ ] **Step 1: Create `esphome/greenhouse-tensiometer.yaml`** with exactly this content:

```yaml
substitutions:
  device_name: "greenhouse-tensiometer"
  friendly_name: "Greenhouse Tensiometer"
  device_ip: "192.168.10.161"
  s1_pin: "GPIO1"        # ADC1_CH0, non-strapping
  s2_pin: "GPIO2"        # ADC1_CH1, non-strapping
  update_interval: "30s"

esphome:
  name: ${device_name}
  friendly_name: ${friendly_name}
  comment: "2x MMM tech TX-E tensiometers (kPa) via 10k/10k dividers on ADC1"

esp32:
  board: esp32-s3-devkitc-1
  flash_size: 16MB
  framework:
    type: arduino

logger:
  level: INFO
  logs:
    sensor: WARN
    api: WARN
    wifi: INFO
    ota: INFO

api:
  encryption:
    key: !secret api_encryption_key

ota:
  - platform: esphome
    password: !secret ota_password

wifi:
  ssid: !secret wifi_ssid
  password: !secret wifi_password
  fast_connect: true
  power_save_mode: none          # steadier ADC on the S3
  manual_ip:
    static_ip: ${device_ip}
    gateway: 192.168.10.1
    subnet: 255.255.255.0
    dns1: 192.168.10.1
  ap:
    ssid: "Tensiometer Fallback"
    password: !secret fallback_password

web_server:
  port: 80

time:
  - platform: sntp
    id: sntp_time
    timezone: "Europe/Oslo"
    servers:
      - pool.ntp.org
      - time.google.com

sensor:
  # ---- Raw divided pin voltages (internal, feed the kPa templates) ----
  - platform: adc
    id: t1_pin_v
    pin: ${s1_pin}
    attenuation: 12db
    update_interval: ${update_interval}
    internal: true
    filters:
      - sliding_window_moving_average: { window_size: 8, send_every: 1 }
  - platform: adc
    id: t2_pin_v
    pin: ${s2_pin}
    attenuation: 12db
    update_interval: ${update_interval}
    internal: true
    filters:
      - sliding_window_moving_average: { window_size: 8, send_every: 1 }

  # ---- Diagnostic: exposed pin voltage (for calibration / fault-spotting) ----
  - platform: template
    name: "1 Volts"
    id: t1_volts
    unit_of_measurement: "V"
    device_class: voltage
    state_class: measurement
    accuracy_decimals: 3
    entity_category: diagnostic
    update_interval: ${update_interval}
    lambda: 'return id(t1_pin_v).state;'
  - platform: template
    name: "2 Volts"
    id: t2_volts
    unit_of_measurement: "V"
    device_class: voltage
    state_class: measurement
    accuracy_decimals: 3
    entity_category: diagnostic
    update_interval: ${update_interval}
    lambda: 'return id(t2_pin_v).state;'

  # ---- Tension in kPa (INVERTED calibrate_linear; clamp 0..100) ----
  - platform: template
    name: "1 kPa"
    id: t1_kpa
    unit_of_measurement: "kPa"
    state_class: measurement
    accuracy_decimals: 1
    icon: mdi:gauge-low
    update_interval: ${update_interval}
    lambda: 'return id(t1_pin_v).state;'
    filters:
      - calibrate_linear:
          - 2.25 -> 0.0        # 4.5 V sensor  = wet
          - 0.25 -> 100.0      # 0.5 V sensor  = dry
      - lambda: |-
          if (isnan(x)) return x;
          if (x < 0.0f) x = 0.0f;
          if (x > 100.0f) x = 100.0f;
          return x;
  - platform: template
    name: "2 kPa"
    id: t2_kpa
    unit_of_measurement: "kPa"
    state_class: measurement
    accuracy_decimals: 1
    icon: mdi:gauge-low
    update_interval: ${update_interval}
    lambda: 'return id(t2_pin_v).state;'
    filters:
      - calibrate_linear:
          - 2.25 -> 0.0
          - 0.25 -> 100.0
      - lambda: |-
          if (isnan(x)) return x;
          if (x < 0.0f) x = 0.0f;
          if (x > 100.0f) x = 100.0f;
          return x;

  # ---- Zone average (NaN-safe) ----
  - platform: template
    name: "Average kPa"
    id: t_avg_kpa
    unit_of_measurement: "kPa"
    state_class: measurement
    accuracy_decimals: 1
    icon: mdi:gauge
    update_interval: ${update_interval}
    lambda: |-
      float a = id(t1_kpa).state;
      float b = id(t2_kpa).state;
      int n = 0; float sum = 0.0f;
      if (!isnan(a)) { sum += a; n++; }
      if (!isnan(b)) { sum += b; n++; }
      return n > 0 ? sum / n : NAN;

  # ---- Standard diagnostics ----
  - platform: wifi_signal
    name: "WiFi Signal"
    update_interval: 60s
    entity_category: diagnostic
  - platform: uptime
    name: "Uptime"
    device_class: duration
    entity_category: diagnostic

binary_sensor:
  - platform: status
    name: "Status"
    device_class: connectivity
  - platform: template
    name: "1 Check Prime"
    id: t1_check_prime
    icon: mdi:water-alert
    lambda: |-
      if (isnan(id(t1_kpa).state)) return {};
      return id(t1_kpa).state > 80.0;   # >~800 hPa: TX-E starts losing water
  - platform: template
    name: "2 Check Prime"
    id: t2_check_prime
    icon: mdi:water-alert
    lambda: |-
      if (isnan(id(t2_kpa).state)) return {};
      return id(t2_kpa).state > 80.0;

button:
  - platform: restart
    name: "Restart"
    entity_category: config

switch:
  - platform: safe_mode
    name: "Safe Mode"
    entity_category: config
```

- [ ] **Step 2: Validate the config** (resolves substitutions + secrets, no hardware needed):

```bash
cd esphome && uvx esphome config greenhouse-tensiometer.yaml 2>&1 | tail -20
```
Expected: the fully-rendered YAML prints with **no errors** (in particular, `!secret` keys resolve and the `calibrate_linear`/lambdas parse).

- [ ] **Step 3: Compile the firmware** (first S3 compile downloads the toolchain — several minutes is normal):

```bash
cd esphome && uvx esphome compile greenhouse-tensiometer.yaml 2>&1 | tail -25
```
Expected: ends with `Successfully compiled program` (a `.bin` under `esphome/.esphome/build/greenhouse-tensiometer/`). Do **not** flash yet.

- [ ] **Step 4: Commit** (named file only):

```bash
git add esphome/greenhouse-tensiometer.yaml
git commit -m "feat(esphome): TX-E tensiometer node config (2ch kPa, native API)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Bench flash + verify the (inverted) calibration on one sensor

De-risks the highest-risk item — the inverted transfer function — on real hardware **before** field install. One sensor + one divider on the bench is enough to prove the whole chain.

**Files:** none (uses Task 1's config).

**Interfaces:**
- Consumes: `esphome/greenhouse-tensiometer.yaml` (Task 1), the entities it produces.

- [ ] **Step 1: [Human] Bench-wire sensor 1.** On a breadboard: TX-E **RED → 5 V**, **BLACK → GND**, **WHITE →[10 kΩ]→ node →[10 kΩ]→ GND**, node → **GPIO1**. Tie all grounds (sensor, divider bottom, ESP32 GND, 5 V-supply GND) together. Prime the tensiometer per the TX-E manual (fill, pump out air, seal — **do not submerge the transducer head**) and stand the **ceramic tip in a cup of water** (= saturated ≈ 0 kPa).

- [ ] **Step 2: Flash over USB** (board on `/dev/cu.usbmodem2101`):

```bash
cd esphome && uvx esphome run greenhouse-tensiometer.yaml --device /dev/cu.usbmodem2101 2>&1 | tail -30
```
Expected: upload succeeds, device boots, joins WiFi at `192.168.10.161`. (If it never joins, switch the wifi secret to `hiwifi_ssid`/`hiwifi_password` per Global Constraints and re-run.)

- [ ] **Step 3: Verify the wet reading.** Open the ESPHome web server `http://192.168.10.161` (or HA → Developer Tools → States). With the tip in water:
  - `1 Volts` ≈ **2.25 V** (± a little), and
  - `sensor.greenhouse_tensiometer_1_kpa` ≈ **0 kPa**.
Expected: near-zero kPa when saturated. (If it reads ~100 kPa when wet, the calibration points are reversed — stop and re-check Task 1.)

- [ ] **Step 4: Verify the direction.** [Human] Lift the tip out of the water into air (or let the cup dry). Watch the values over 1–2 min.
Expected: `1 Volts` **falls** and `..._1_kpa` **rises** — confirming higher kPa = drier. This is the whole point of the inverted map; it must move this way.

- [ ] **Step 5: Record the prime-zero offset.** Note the kPa reading at the moment it's freshly primed and saturated. If it's not ~0 (a small hydrostatic offset from the 30 cm column is expected, ≲3 kPa), record the value — Task 4 trims it out. No code change here unless it's large (> ~5 kPa), in which case adjust the `2.25 ->` wet point to the observed wet-volts and re-flash.

- [ ] **Step 6: Commit** any calibration tweak (skip if none):

```bash
git add esphome/greenhouse-tensiometer.yaml
git commit -m "fix(esphome): trim TX-E prime-zero offset from bench test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Metrics-dashboard card (soil-tension gauge + dryback trend)

**Files:**
- Modify: `configs/homeassistant/ui-lovelace.yaml` (append a card group to the existing **Metrics** view, `path: metrics`)

**Interfaces:**
- Consumes: `sensor.greenhouse_tensiometer_1_kpa`, `_2_kpa`, `_average_kpa`, `binary_sensor.greenhouse_tensiometer_{1,2}_check_prime` (Task 1).

- [ ] **Step 1: Append the cards** to the Metrics view (after its last card, keeping the view's `cards:` indentation):

```yaml
      - type: gauge
        entity: sensor.greenhouse_tensiometer_average_kpa
        name: Soil tension (avg)
        min: 0
        max: 50
        needle: true
        # PROVISIONAL bands — higher kPa = drier. Real setpoints come in Phase 2
        # from the crop-water-potential reference + the baseline.
        severity:
          green: 0
          yellow: 10
          red: 25
      - type: history-graph
        title: 🌱 Soil tension — dryback
        hours_to_show: 24
        entities:
          - entity: sensor.greenhouse_tensiometer_1_kpa
            name: Sensor 1
          - entity: sensor.greenhouse_tensiometer_2_kpa
            name: Sensor 2
          - entity: sensor.greenhouse_tensiometer_average_kpa
            name: Average
      - type: entities
        title: 🌱 Tensiometers
        entities:
          - entity: sensor.greenhouse_tensiometer_1_kpa
            name: Sensor 1 tension
          - entity: sensor.greenhouse_tensiometer_2_kpa
            name: Sensor 2 tension
          - entity: binary_sensor.greenhouse_tensiometer_1_check_prime
            name: Sensor 1 — refill/re-prime?
          - entity: binary_sensor.greenhouse_tensiometer_2_check_prime
            name: Sensor 2 — refill/re-prime?
```

- [ ] **Step 2: Deploy + YAML-lint + reload:**

```bash
rsync -avz configs/homeassistant/ui-lovelace.yaml greenhouse:/opt/greenhouse/config/homeassistant/
cat configs/homeassistant/ui-lovelace.yaml | ssh greenhouse "docker exec -i greenhouse_homeassistant python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin); print(\"OK\")'"
```
Expected: `OK`. Then trigger a Lovelace reload (HA WebSocket `lovelace/config` with `force: true`, or reload the dashboard in the UI) → the Metrics view shows the gauge + dryback graph + tensiometer entities.

- [ ] **Step 3: Commit:**

```bash
git add configs/homeassistant/ui-lovelace.yaml
git commit -m "feat(dashboard): tensiometer gauge + dryback trend on Metrics view

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Field install (2 sensors) + field-zero + docs + baseline kickoff

**Files:**
- Modify: `CLAUDE.md` (device list + network IP table)

**Interfaces:**
- Consumes: everything from Tasks 1–3.

- [ ] **Step 1: [Human] Install both tensiometers.** Site each in a representative 20 L pot, ceramic tip in the **main root zone (~20 cm deep)**, **~5 cm beside a dripper**. Prime both per the TX-E manual. Wire sensor 1 → GPIO1 divider, sensor 2 → GPIO2 divider (10 k/10 k each), both RED → 5 V, both BLACK → GND, **all grounds common**. Mount the S3 node within the 3 m cable reach, away from power/PWM wiring.

- [ ] **Step 2: Confirm both channels report.** In HA States / `http://192.168.10.161`, verify `..._1_kpa` and `..._2_kpa` both read plausible tension for freshly-watered pots (low kPa), and `..._average_kpa` is their mean.
Expected: two live channels + average, all non-`unavailable`.

- [ ] **Step 3: Field-zero.** For each sensor, right after priming while the substrate is saturated, confirm it reads ~0 kPa. If a sensor sits at a constant small offset (≲3 kPa), trim it: set that channel's `2.25 ->` wet point to the observed saturated pin-voltage (read the `N Volts` diagnostic) and re-flash via OTA:
```bash
cd esphome && uvx esphome run greenhouse-tensiometer.yaml --device 192.168.10.161 2>&1 | tail -15
```
(Commit the tweak with a `fix(esphome): field-zero sensor N` message.)

- [ ] **Step 4: Update `CLAUDE.md`.** Add to the ESP32 device-types list a **Tensiometer Node**: "ESP32-S3, 2× MMM tech TX-E electronic tensiometers (0.5–4.5 V, inverted: 4.5 V=0 kPa/0.5 V=100 kPa) via 10 k/10 k dividers on GPIO1/GPIO2, native API, kPa + average." Add to the Network IP table: `192.168.10.161: greenhouse-tensiometer`.

- [ ] **Step 5: Commit:**

```bash
git add CLAUDE.md
git commit -m "docs: register tensiometer node (.161) in CLAUDE.md device list

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 6: Kick off the baseline.** Note today's date; the node now logs to the HA recorder (MariaDB, 365-day retention). Plan to review ~1–2 weeks of dryback data (drying rate vs the growth-program kPa bands) before starting Phase 2 (the parked deficit-irrigation design). No further action — just let it record. Update memory `greenhouse-automation-state` to reflect tensiometers installed + baseline running.

---

## Self-Review (author)

- **Spec coverage:** node/hardware (Global Constraints + Task 1) ✓; inverted transfer function + divider + calibrate_linear (Task 1 Step 1, verified Task 2) ✓; 2 channels + NaN-safe average + volts diagnostics + >80 kPa check-prime (Task 1) ✓; native-API entities (Task 1) ✓; dashboard gauge + trend, no setpoints (Task 3) ✓; deploy/flash via uvx, static .161, CLAUDE.md, baseline (Task 4) ✓; **no automation** (stated, none added) ✓; field-zero/prime offset (Task 2 Step 5, Task 4 Step 3) ✓.
- **Placeholder scan:** all YAML, lambdas, calibrate_linear points, and commands are literal; physical actions marked **[Human]**; no TBD/TODO.
- **Type/id consistency:** entity ids `sensor.greenhouse_tensiometer_{1,2,average}_kpa`, `_{1,2}_volts`, `binary_sensor.greenhouse_tensiometer_{1,2}_check_prime` used identically in Task 1 (produced), Task 3 (dashboard), Task 4 (verify). Pins GPIO1/GPIO2, IP .161, divider 10 k/10 k, cal `[2.25->0, 0.25->100]` consistent throughout and against the spec/Global Constraints.
- **Deferred-to-runtime (flagged, not placeholders):** WiFi SSID choice (Hi-Wifi gotcha) and per-sensor prime-zero trim — both have explicit resolution steps.
