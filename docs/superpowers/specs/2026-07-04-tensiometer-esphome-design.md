# Tensiometer ESPHome Node — Design (Phase 1: sensing + baseline logging)

**Date:** 2026-07-04
**Status:** Approved (design), pending spec review
**Unblocks:** [[docs/superpowers/specs/2026-07-01-tensiometer-irrigation-design.md]] (the parked
deficit-irrigation plan). This is its **Phase 1** — "wire → ESPHome → publish kPa to HA → collect
~1–2 weeks baseline." The irrigation automation stays **parked** until the baseline is in.

## Context

The greenhouse runs Home Assistant + ESPHome nodes (soil monitors on MQTT, `climate-2` on the native
API). Watering today is a blind fixed time schedule on `switch.plugg_1_vanning`, dormant behind
`input_boolean.gh_watering_ha_enabled`. The parked design's blocker was "no substrate feedback." The
user has now bought 5 MMM tech **TX-E** electronic tensiometers and is installing the first 2 —
closing that gap.

**This spec covers only getting 2 tensiometers reporting reliable soil-water-tension (kPa) into HA
and starting the baseline log.** No irrigation logic, no setpoints, no per-variety zoning — those are
Phase 2/3, informed by the baseline data plus the crop-water-potential references.

## Goals

1. A dedicated ESPHome node reads 2× TX-E tensiometers and publishes `kPa` (soil water tension) plus a
   zone average to HA via the native API.
2. Correct, documented calibration (the TX-E transfer function is **inverted** — see below).
3. A small dashboard trend so the dryback curve can be watched as history accumulates.
4. Zero disturbance to the working soil-monitor and existing automations.

## Non-goals

- Irrigation automation / trigger pulsing / setpoints (parked — Phase 2).
- Per-variety (Sun Gold vs Black Cherry) zoning decisions (Phase 3, needs the valve-mapping answer).
- Drain %, DLI, EC, or any other new metric.
- Reworking the soil-monitor or moving the moisture sensors.

---

## Hardware

### Node
- **Dedicated ESP32-S3 devkit**, already on hand and verified over USB:
  ESP32-S3 (QFN56) rev v0.1, **16 MB flash + 8 MB PSRAM (N16R8)**, native USB-Serial/JTAG,
  MAC `34:85:18:75:e8:98`.
- ESPHome: `board: esp32-s3-devkitc-1`, `flash_size: 16MB`, `framework: arduino` (matches the
  valve-controller / fertigation nodes). PSRAM left unconfigured (unused, fine).
- Mains-powered → provides the **regulated 5.0 V** rail the sensors require.
- First flash over USB (`/dev/cu.usbmodem2101`); OTA thereafter.

### Sensors — MMM tech TX-E (electronic tensiometer, no manometer)
Confirmed from the TX-E supplementary manual + the factory Pressure↔Signal lookup table:

| Property | Value |
|---|---|
| Measurement range | 0…−1000 hPa = **0–100 kPa** tension (relative to atmosphere) |
| Output | **0.5–4.5 V, linear, ratiometric** (rides on the 5 V supply) |
| **Transfer function** | **4.50 V = 0 kPa (wet)** · **0.50 V = 100 kPa (dry)** · 4 mV/hPa = 40 mV/kPa |
| Supply | **5.0 VDC — never exceed** |
| Accuracy / resolution | ±1 % of span / 1 hPa (0.1 kPa) |
| Excitation delay | 300 ms after power-on (non-issue: continuously powered) |
| Cable / leads | 3 m open leads — **RED = +5 V, BLACK = GND, WHITE = signal** |
| Other | IP67, stainless; no temperature correction; no periodic calibration; shaft 30 cm |

> **⚠️ The transfer function is inverted** — voltage *falls* as the soil dries. (The product web page
> only says "0.5–4.5 V"; the supplementary manual gives the direction. Getting this backwards would
> mirror-image every reading.)

**Precautions:** never submerge the transducer head in water (it sits at the shaft top, cabled);
never exceed 5.0 V; protect the ceramic tip from grease/oil and from shocks.

### Signal conditioning — voltage divider (required)
The 0.5–4.5 V output exceeds the S3 ADC's ~3.3 V limit, so each channel needs a divider.

- **10 kΩ (top) + 10 kΩ (bottom)** per sensor → **0.5 ratio** (from the user's Luxorparts ±1 % kit).
- Pin voltage: **2.25 V (wet / 0 kPa) → 0.25 V (dry / 100 kPa)** — centered in the S3 ADC's linear
  band; ~5 kΩ source impedance (within ADC spec). No RC cap (firmware moving-average handles noise).

```
 TX-E WHITE  ──[ 10kΩ ]──┬──[ 10kΩ ]── GND
 (0.5–4.5 V)             │
                         └───────────────►  ESP32-S3 ADC pin
 TX-E RED    ─────────────────────────────►  +5.0 V (regulated)
 TX-E BLACK  ─────────────────────────────►  GND
```

- **Common ground is mandatory:** sensor BLACK, divider bottom leg, ESP32 GND, and the 5 V supply GND
  all tied together.
- **Pins:** Sensor 1 → **GPIO1** (ADC1_CH0), Sensor 2 → **GPIO2** (ADC1_CH1). Both ADC1 (WiFi-safe)
  and non-strapping. GPIO4+ free for a 3rd TX-E later. (Avoid strapping pins GPIO0/3/45/46; ADC2 is
  unusable with WiFi.)

### Placement (from the TX-E / TX manuals)
- Representative pot, ceramic tip in the **main root zone (~20 cm deep)**, **~5 cm beside a dripper**.
- 2 sensors now for averaging/redundancy (the manual recommends **3 per management unit**; a 3rd is an
  easy add). Air ingress is the classic failure — 2 lets one cross-check the other.
- 3 m cable → node may sit up to ~3 m from the pots; route analog leads away from power/PWM wiring.

---

## Firmware — `esphome/greenhouse-tensiometer.yaml`

Native-API node (auto-discovery into HA, like `climate-2`), standard components per CLAUDE.md.

**Per sensor (×2):**
- `adc` on GPIO1/GPIO2, `attenuation: 12db`, read as **volts** (internal id), `update_interval: 30s`,
  `sliding_window_moving_average` (window ~8) to smooth ADC noise.
- Template `sensor` "GH Tensiometer N kPa" → feeds the pin volts through
  `calibrate_linear: [2.25 -> 0.0, 0.25 -> 100.0]`, then clamps 0–100 kPa, `accuracy_decimals: 1`,
  `state_class: measurement`, `icon: mdi:gauge-low`.
- The pin voltage is **also** exposed as a `diagnostic` sensor ("GH Tensiometer N Volts") for
  calibration/debug and to spot a disconnected/failed sensor.

**Derived:**
- Template `sensor` "GH Tensiometer Average kPa" — NaN-safe mean of the two (mirrors the soil-monitor
  `Average Soil VWC` pattern).
- Template `binary_sensor` "GH Tensiometer N Check Prime" — `true` when kPa > 80 (approaching the
  ~800 hPa air-entry where the TX-E loses water) → surfaces the manual's refill/maintenance need.

**Zero / prime offset:** a freshly-primed, saturated tensiometer should read ~0 kPa. There is a small
hydrostatic offset from the 30 cm water column (theoretically ~3 kPa; the TX/TX-E manuals note
"subtract the shaft length"). Handle it by **field-zero at prime**: after priming, read the value; if
non-zero, trim it out (adjust the `2.25 →` wet point, or subtract a small constant). Documented as a
verification step, not hard-coded, so it's set from the real reading.

**Standard components (per CLAUDE.md):** static IP, `api` (encryption), `ota` (password), `web_server`,
`sntp` (Europe/Oslo), `wifi_signal`, `uptime`, `binary_sensor: status`, `restart` button,
`safe_mode` switch. **Note:** the S3 devkit's onboard LED is an addressable WS2812 on GPIO48, not a
plain GPIO LED — `status_led:` is **omitted** in Phase 1 (diagnostic entities + `web_server` cover
status); can be added later as a `light`.

**Target HA entities** (native API): `sensor.gh_tensiometer_1_kpa`, `sensor.gh_tensiometer_2_kpa`,
`sensor.gh_tensiometer_avg_kpa`, plus `_volts` diagnostics and `binary_sensor.gh_tensiometer_*_check_prime`.
(Names chosen for the `gh_*` convention used by the metrics package; the plan confirms exact slugs.)

### Skeleton (illustrative — the implementation plan finalizes exact YAML)

```yaml
substitutions:
  device_ip: "192.168.10.161"
  s1_pin: "GPIO1"
  s2_pin: "GPIO2"

esp32:
  board: esp32-s3-devkitc-1
  flash_size: 16MB
  framework:
    type: arduino

api:
  encryption:
    key: !secret api_encryption_key
# ota / wifi (static IP .161) / web_server / sntp / diagnostics per the standard pattern

sensor:
  - platform: adc
    id: t1_pin_v
    pin: ${s1_pin}
    attenuation: 12db
    update_interval: 30s
    internal: true
    filters:
      - sliding_window_moving_average: { window_size: 8, send_every: 1 }
  - platform: template
    name: "GH Tensiometer 1 kPa"
    id: t1_kpa
    unit_of_measurement: "kPa"
    state_class: measurement
    accuracy_decimals: 1
    icon: mdi:gauge-low
    update_interval: 30s
    lambda: 'return id(t1_pin_v).state;'   # pin volts → calibrate below
    filters:
      - calibrate_linear:
          - 2.25 -> 0.0      # 4.5 V sensor (wet)
          - 0.25 -> 100.0    # 0.5 V sensor (dry)
      - lambda: 'if (x < 0) x = 0; if (x > 100) x = 100; return x;'
  # (identical block for sensor 2 on ${s2_pin}; a diagnostic "Volts" sensor per channel;
  #  a NaN-safe average template; and the >80 kPa "check prime" binary_sensors)
```

---

## Home Assistant integration

- **Native API only.** No `mqtt.yaml` edits; the HA recorder logs the entities to MariaDB (365-day
  retention) — that *is* the baseline history.
- **Dashboard (minimal, Phase 1):** add to the existing **Metrics** view (or a small "🌱 Substrate"
  card): a **kPa gauge** for the average (0–50 kPa scale for resolution; **higher = drier**, so bands
  are inverted vs the moisture gauges) + a **24 h / 7 d trend** of the two channels + average. Built-in
  cards (`gauge`, `history-graph`) or `mini-graph-card` if already installed.
- **Setpoint bands are deliberately NOT set here** — the green/yellow/red thresholds come in Phase 2
  from the crop-water-potential reference + what the baseline shows the substrate actually does.
- Optional (can fold into the metrics package during baseline analysis): `statistics` min/max/mean
  (24 h, 7 d) on the average for a cleaner dryback curve.

---

## Deployment

1. Create `esphome/greenhouse-tensiometer.yaml`.
2. **Static IP `192.168.10.161`** (free; .150–.155 sensors, .160 valve, .200 fertigation are taken).
3. **Confirm the WiFi secret / SSID at deploy** — the `Hi-Wifi` vs `HiWiFi` gotcha; match whichever
   network reaches the node's location (valve/soil use `wifi_ssid`; `climate-2` uses `hiwifi_ssid`).
4. Reuses existing `secrets.yaml` (`api_encryption_key`, `ota_password`, wifi creds, `fallback_password`).
   *(Note: the shared `api_encryption_key`/HA token rotation is a separate pending action; the new node
   uses the current key so it pairs immediately.)*
5. Flash: `uvx esphome run greenhouse-tensiometer.yaml` over USB for the first flash, OTA after
   (global `esphome` CLI is broken — use `uvx`; flash from the Mac).
6. Add the node to the CLAUDE.md device list + the IP table.
7. **No changes to `automations.yaml`** — deficit-irrigation stays parked.

---

## Calibration & verification

1. **Bench test each sensor before install:** power at 5 V, measure WHITE↔BLACK with a multimeter →
   ~4.5 V with the freshly-primed tip in water (0 kPa), falling as it dries. Then verify the divided
   pin voltage ≈ 2.25 V. (Matches the manual's "multimeter-test before install" tip.)
2. **After flash:** the 3 kPa entities + diagnostics appear in HA; pin volts plausible; `avg_kpa` ≈ 0
   when primed/saturated; kPa **rises** as a pot dries (confirms the inverted mapping is right).
3. **Field-zero:** set the prime offset so a saturated, freshly-primed sensor reads ~0 kPa.
4. **Baseline:** log **~1–2 weeks** of dryback; compare the real substrate drying rate against the
   growth-program kPa bands. This dataset is the input to Phase 2.

## Risks / caveats

- **Ratiometric output** → accuracy tracks the 5 V rail; use a stable regulated 5.0 V (a hair under is
  safer than over). Ratiometric correction (measure the rail) can be added later if drift appears.
- **Shaft/prime offset (~3 kPa)** — removed by field-zero at prime, not hard-coded.
- **Air ingress when very dry (>~80 kPa)** — the "check prime" flag + the growth program's weekly
  refill check cover it.
- **ADC noise** — mitigated by the moving-average; tension is a slow signal. ADC1-only (ADC2 avoided).
- **Long analog runs** — keep ≤ 3 m (cable length); route away from power/PWM lines.
- **Substrate ≠ mineral soil** — the peat/wood-fibre pots steer at lower tensions than the TX manual's
  mineral-soil colour bands; that only affects Phase 2 setpoints, not Phase 1 sensing.

## Verification checklist (definition of done for Phase 1)

- [ ] `esphome config` / compile clean; node flashes and comes online at `.161`.
- [ ] `sensor.gh_tensiometer_1_kpa`, `_2_kpa`, `_avg_kpa` present in HA with plausible values.
- [ ] Wet/dry test moves kPa in the correct direction (up = drier).
- [ ] Prime-zero verified (~0 kPa saturated).
- [ ] Dashboard trend renders; history begins accumulating.
- [ ] Existing soil-monitor + automations untouched.
