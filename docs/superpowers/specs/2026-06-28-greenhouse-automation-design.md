# Greenhouse Climate & Irrigation Automation — Design

**Date:** 2026-06-28
**Status:** Approved (design), pending spec review

## Context

400 m² poly tunnel, Sun Gold & Black Cherry tomatoes (~220 plants), currently ~Stage 5–6
(GH establish / flowering) of the Consolidated Growth Program 2026. Today's automation is
**fixed schedules in the Tapo app**, blind to conditions:
- Watering (drip, 2 L/h nozzles): 07:00–07:20, 09:00–09:15, 11:00–11:10, 13:00–13:10, 15:00–15:15
- Fans: on 07:00, off 18:00

**Control surface (HA):**
- Fans: `switch.plugg_3_vifte_endevegg_ost`, `switch.plugg_5_vifte_endevegg_vest` (on/off, run as a pair)
- Watering: `switch.plugg_1_vanning` (on/off pump)
- Climate sensor: `sensor.greenhouse_climate_2_temperature`, `sensor.greenhouse_climate_2_humidity`, `binary_sensor.greenhouse_climate_2_device_status`
- Forecast: `weather.forecast_hjem`; Sun: `sun.sun` (for sunset-relative timing)
- Roll-up wall: **motorized but NOT wired to HA** → alert-based for now
- No greenhouse heating (the "heater" ESPs are in the seedling rooms, out of scope)

**Program targets (current stage):** Day **22–25 °C**, Night **17–18.5 °C** (deliberate 4–7 °C
day/night drop for flavor); RH **60–80 %** (~70 % ideal); **below 30 °C** for pollination
(>80 % RH clumps pollen, <60 % dries stigma). **BER from uneven watering is the #1 quality
risk** → irrigation must stay steady; program wants last irrigation ~2–3 h before sunset
(evening dryback for Brix). Sun Gold is split-prone → keep on the wetter side.

## Approach

Hybrid: **react to live sensor data** for fan control; **use the forecast** for pre-emptive
alerts and gentle watering nudges. Conservative on watering (BER risk + only air sensors).

## Goals
1. Replace the fixed fan schedule with temp/humidity-driven control + daylight circulation.
2. Push alerts (HA companion app) for overheat, cold, humidity extremes, sensor offline, and
   roll-up-wall open/close prompts.
3. Migrate watering into HA: same 5 pulses + a gentle forecast nudge + sunset-aware last pulse.
4. Make thresholds tunable from the dashboard (helpers) with a master on/off.

## Non-goals
- Automating the roll-up wall motor (not wired to HA yet — alerts only; auto-control later).
- Heating / frost actuation (no greenhouse heaters).
- Soil-moisture / tensiometer-driven irrigation (no such sensors yet).

## Components

### Helpers (tunable from dashboard)
- `input_boolean.gh_automation_enabled` — master switch (pauses all climate/watering automations)
- `input_number.gh_fan_on_temp` (default 25 °C), `gh_fan_off_temp` (23), `gh_humidity_max` (80),
  `gh_humidity_off` (72), `gh_overheat_temp` (30), `gh_overheat_critical` (35), `gh_cold_temp` (12)

### A. Fan control (replaces fixed 07:00–18:00)
Drives both Vifte plugs together. Triggered on temp/humidity change and a periodic 5-min check.
- **ON** if `temp ≥ gh_fan_on_temp` OR `humidity ≥ gh_humidity_max`
- **OFF** if `temp ≤ gh_fan_off_temp` AND `humidity ≤ gh_humidity_off` (hysteresis prevents chatter)
- **Daylight circulation**: when `sun.sun = above_horizon` and fans would otherwise be off, run
  ~10 min/hour for air movement (pollination + botrytis prevention)
- **Night**: fans off (allow the cool-night drop) EXCEPT humidity guard (`humidity > 85` → run)
- Gated by `gh_automation_enabled` and by `device_status = on` (don't act on stale data)

### B. Safety alerts (push + persistent)
- `temp ≥ gh_overheat_temp` (30) → "Pollination at risk — open the roll-up wall"
- `temp ≥ gh_overheat_critical` (35) → urgent "Greenhouse overheating"
- `temp ≤ gh_cold_temp` (12) → cold alert
- Re-notify rate-limited (e.g., not more than every 30 min per condition)

### C. Roll-up wall prompts (push; not HA-controlled yet)
- **Open**: temp climbing past ~27 °C OR forecast daytime high indicates a hot day
- **Close**: evening temp dropping toward night target, OR forecast rain / strong wind / cold
- Worded as actionable prompts; become automatic when the motor is wired in.

### D. Humidity / pollination alerts (push, daytime)
- `humidity > 85 %` (botrytis) or `humidity < 55 %` (stigma dries) → alert

### E. Sensor-offline alert
- `binary_sensor.greenhouse_climate_2_device_status` off / unavailable for > 15 min → alert
  (also suppresses A–D acting on stale data)

### F. Watering (steady + forecast nudge, moved into HA)
- Recreate the 5 base pulses as time-triggered automations toggling `switch.plugg_1_vanning`
  for the existing durations (20/15/10/10/15 min)
- **Forecast nudge** (gentle, ±1 pulse): hot + sunny next-day/again → one short extra evening
  pulse; cool / rainy → trim/skip one midday pulse
- **Sunset-aware last pulse**: shift/add the final pulse to ~2–3 h before `sun.sun` next setting
  (replaces the 15:15 stop, which leaves a ~7 h dry afternoon — bad for BER and dryback)
- Gated by `gh_automation_enabled`. **Tapo-app watering schedule must be disabled** to avoid conflict.

### G. Dashboard
- New "Automation & Climate" section: master toggle, the threshold `input_number`s, current
  fan/watering state, and next watering time.

## Notifications
HA companion app push via `notify.mobile_app_*` (exact service resolved at implementation) plus
`persistent_notification.create` for an in-HA record. Critical alerts rate-limited.

## Safety & risk
- **BER**: watering stays steady; nudge is gentle (±1 pulse) and respects Sun Gold's wetter bias.
- **Relay wear/chatter**: hysteresis on fan thresholds + periodic (not continuous) evaluation.
- **Stale data**: all control gated on `device_status = on`.
- **One sensor for 400 m²**: single-point reading; gradients exist. Acceptable now; note for future
  multi-sensor expansion. Thresholds tunable via helpers as the user calibrates.
- **Master kill switch** (`gh_automation_enabled`) to pause everything during maintenance.

## Phased implementation
- **Phase 1**: helpers + fan control (A) + safety/humidity/offline alerts (B, D, E). Core wins, zero crop risk.
- **Phase 2**: roll-up wall prompts (C).
- **Phase 3**: watering migration + nudge + sunset-aware pulse (F). Requires disabling Tapo schedule.
- Dashboard section (G) added alongside Phase 1 and extended per phase.

## Verification
- Per automation: trace with HA's automation trace; force conditions by temporarily setting helper
  thresholds around the current reading and confirm fans actuate + alerts fire.
- Confirm hysteresis (no rapid toggling) over a temp sweep.
- Confirm `gh_automation_enabled = off` halts all actions.
- HA config check passes; no "unknown entity" errors.
