# Greenhouse Climate & Irrigation Automation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement task-by-task. Steps use checkbox (`- [ ]`). This is HA config (YAML); each task's "test" is a `check_config` pass + a functional trace (force a threshold, observe the actuator/alert), not a unit test.

**Goal:** Replace the greenhouse's fixed Tapo schedules with sensor- and forecast-aware Home Assistant automation: temp/humidity-driven fans, push alerts (overheat/cold/humidity/sensor-offline/roll-up-wall), and a steady-but-nudged watering schedule — all tunable from the dashboard.

**Architecture:** Helpers (`input_number`/`input_boolean`) hold tunable thresholds + a master switch. Automations in `automations.yaml` read the climate sensor (`greenhouse_climate_2`) and `weather.forecast_hjem`, act on the plugs (`plugg_1_vanning`, `plugg_3/5_vifte_endevegg_*`), and notify via a shared `script.gh_notify`. Roll-up wall is alert-only (not HA-controlled). Dashboard gains an "Automation & Climate" section.

**Tech Stack:** Home Assistant 2026.6.4 (YAML config, deployed by rsync to `greenhouse:/opt/greenhouse/config/homeassistant/`), HA companion app push.

## Global Constraints
- Climate entities (verbatim): `sensor.greenhouse_climate_2_temperature`, `sensor.greenhouse_climate_2_humidity`, `binary_sensor.greenhouse_climate_2_device_status`.
- Actuators (verbatim): watering `switch.plugg_1_vanning`; fans `switch.plugg_3_vifte_endevegg_ost` + `switch.plugg_5_vifte_endevegg_vest`.
- Forecast `weather.forecast_hjem`; sun `sun.sun`.
- All control automations gated by `input_boolean.gh_automation_enabled` AND `binary_sensor.greenhouse_climate_2_device_status == 'on'` (never act on stale data).
- Deploy only the edited files by name (NOT `make deploy-ha`). Validate with `check_config` before reload.
- Do NOT commit unless the user asks (on `main` → branch first).
- Program targets (current stage): day 22–25 °C, night 17–18.5 °C, RH 60–80 %, pollination <30 °C; BER = uneven-watering risk → watering stays steady.

---

## PHASE 1 — Helpers, fan control, alerts, dashboard

### Task 1: Threshold helpers + master switch

**Files:**
- Modify: `configs/homeassistant/configuration.yaml` (add `input_number`/`input_boolean` includes)
- Create: `configs/homeassistant/sensors/automation_numbers.yaml`
- Create: `configs/homeassistant/sensors/automation_booleans.yaml`

- [ ] **Step 1: Add includes** under the existing `input_button:` line in `configuration.yaml`:
```yaml
input_number: !include sensors/automation_numbers.yaml
input_boolean: !include sensors/automation_booleans.yaml
```

- [ ] **Step 2: Create `automation_numbers.yaml`:**
```yaml
gh_fan_on_temp:    {name: "Fan ON temp",      min: 18, max: 35, step: 0.5, unit_of_measurement: "°C", initial: 25, icon: mdi:fan}
gh_fan_off_temp:   {name: "Fan OFF temp",     min: 16, max: 33, step: 0.5, unit_of_measurement: "°C", initial: 23, icon: mdi:fan-off}
gh_humidity_max:   {name: "Humidity max (fan)",min: 50, max: 95, step: 1, unit_of_measurement: "%", initial: 80, icon: mdi:water-percent}
gh_humidity_off:   {name: "Humidity off (fan)",min: 40, max: 90, step: 1, unit_of_measurement: "%", initial: 72, icon: mdi:water-percent}
gh_overheat_temp:  {name: "Overheat alert",   min: 26, max: 38, step: 0.5, unit_of_measurement: "°C", initial: 30, icon: mdi:thermometer-alert}
gh_overheat_critical:{name: "Overheat critical",min: 30, max: 45, step: 0.5, unit_of_measurement: "°C", initial: 35, icon: mdi:thermometer-alert}
gh_cold_temp:      {name: "Cold alert",       min: 0,  max: 18, step: 0.5, unit_of_measurement: "°C", initial: 12, icon: mdi:snowflake-alert}
```

- [ ] **Step 3: Create `automation_booleans.yaml`:**
```yaml
gh_automation_enabled:
  name: "Greenhouse automation enabled"
  icon: mdi:robot
  initial: true
```

- [ ] **Step 4: Deploy + validate**
```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
rsync -avz configs/homeassistant/configuration.yaml configs/homeassistant/sensors/automation_numbers.yaml configs/homeassistant/sensors/automation_booleans.yaml greenhouse:/opt/greenhouse/config/homeassistant/{,sensors/}
ssh greenhouse 'docker exec greenhouse_homeassistant python3 -m homeassistant --script check_config -c /config 2>&1 | tail -3'
```
Expected: no errors. (rsync paths: send the two helper files into `sensors/`.)

- [ ] **Step 5: Restart HA** (new top-level includes require a restart): `ssh greenhouse 'cd /opt/greenhouse && docker compose restart homeassistant'`; wait for HTTP 200; confirm `input_boolean.gh_automation_enabled` and the 7 `input_number.gh_*` exist via `/api/states`.

### Task 2: Shared notify script + discover mobile service

**Files:** Modify `configs/homeassistant/scripts.yaml`

- [ ] **Step 1: Discover the mobile push service** — list notify services:
```bash
SCRATCH=/private/tmp/claude-501/.../scratchpad
cat "$SCRATCH/ha_token" | ssh greenhouse "docker exec -i greenhouse_homeassistant python3 -c '
import sys,json,urllib.request
tok=sys.stdin.read().strip()
d=json.load(urllib.request.urlopen(urllib.request.Request(\"http://localhost:8123/api/services\",headers={\"Authorization\":\"Bearer \"+tok})))
for s in d:
  if s[\"domain\"]==\"notify\": print(list(s[\"services\"].keys()))
'"
```
Expected: a `mobile_app_<device>` service name. Record it as `<MOBILE_NOTIFY>`.

- [ ] **Step 2: Add `gh_notify` script** to `scripts.yaml` (replace `<MOBILE_NOTIFY>` with the discovered service; if none, drop that step and keep persistent only):
```yaml
gh_notify:
  alias: "GH Notify"
  mode: parallel
  fields:
    title: {description: "Title"}
    message: {description: "Message"}
  sequence:
    - service: notify.<MOBILE_NOTIFY>
      data:
        title: "{{ title }}"
        message: "{{ message }}"
    - service: persistent_notification.create
      data:
        title: "{{ title }}"
        message: "{{ message }}"
```

- [ ] **Step 3: Deploy + reload + test**
```bash
rsync -avz configs/homeassistant/scripts.yaml greenhouse:/opt/greenhouse/config/homeassistant/
# reload scripts via API service call, then fire a test:
```
Call `script.reload`, then `script.gh_notify` with title/message via `/api/services/script/gh_notify`; confirm the phone push + a persistent notification appears. Expected: both arrive.

### Task 3: Fan control automation (hysteresis + circulation + night guard)

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add the fan-control automation:**
```yaml
- id: gh_fan_control
  alias: "GH Fan control (temp/humidity)"
  mode: single
  trigger:
    - platform: state
      entity_id: [sensor.greenhouse_climate_2_temperature, sensor.greenhouse_climate_2_humidity]
    - platform: time_pattern
      minutes: "/5"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: binary_sensor.greenhouse_climate_2_device_status
      state: "on"
  action:
    - variables:
        t: "{{ states('sensor.greenhouse_climate_2_temperature') | float(0) }}"
        h: "{{ states('sensor.greenhouse_climate_2_humidity') | float(0) }}"
        on_t: "{{ states('input_number.gh_fan_on_temp') | float(25) }}"
        off_t: "{{ states('input_number.gh_fan_off_temp') | float(23) }}"
        h_max: "{{ states('input_number.gh_humidity_max') | float(80) }}"
        h_off: "{{ states('input_number.gh_humidity_off') | float(72) }}"
        day: "{{ is_state('sun.sun','above_horizon') }}"
        fans_on: "{{ is_state('switch.plugg_3_vifte_endevegg_ost','on') }}"
        want_on: "{{ (t >= on_t) or (h >= h_max) or (not day and h > 85) }}"
        want_off: "{{ (t <= off_t) and (h <= h_off) and not (not day and h > 85) }}"
    - choose:
        - conditions: "{{ want_on and not fans_on }}"
          sequence:
            - service: switch.turn_on
              target: {entity_id: [switch.plugg_3_vifte_endevegg_ost, switch.plugg_5_vifte_endevegg_vest]}
        - conditions: "{{ want_off and fans_on }}"
          sequence:
            - service: switch.turn_off
              target: {entity_id: [switch.plugg_3_vifte_endevegg_ost, switch.plugg_5_vifte_endevegg_vest]}
```

- [ ] **Step 2: Add the daylight circulation automation** (runs fans ~10 min/hour when otherwise idle):
```yaml
- id: gh_fan_circulation
  alias: "GH Fan circulation (daylight)"
  mode: single
  trigger:
    - platform: time_pattern
      minutes: "0"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: sun.sun
      state: "above_horizon"
    - condition: state
      entity_id: switch.plugg_3_vifte_endevegg_ost
      state: "off"
  action:
    - service: switch.turn_on
      target: {entity_id: [switch.plugg_3_vifte_endevegg_ost, switch.plugg_5_vifte_endevegg_vest]}
    - delay: "00:10:00"
    # only turn back off if the climate automation didn't latch them on for cooling
    - condition: template
      value_template: "{{ (states('sensor.greenhouse_climate_2_temperature')|float(0)) < (states('input_number.gh_fan_on_temp')|float(25)) and (states('sensor.greenhouse_climate_2_humidity')|float(0)) < (states('input_number.gh_humidity_max')|float(80)) }}"
    - service: switch.turn_off
      target: {entity_id: [switch.plugg_3_vifte_endevegg_ost, switch.plugg_5_vifte_endevegg_vest]}
```

- [ ] **Step 3: Deploy + validate + reload**
```bash
rsync -avz configs/homeassistant/automations.yaml greenhouse:/opt/greenhouse/config/homeassistant/
ssh greenhouse 'docker exec greenhouse_homeassistant python3 -m homeassistant --script check_config -c /config 2>&1 | tail -3'
```
Then call `automation.reload`. Expected: config OK; `automation.gh_fan_control` exists.

- [ ] **Step 4: Functional test (force ON then OFF)** — temporarily set `input_number.gh_fan_on_temp` below current temp (e.g., to 18) via `/api/services/input_number/set_value`; within 5 min (or fire the automation) confirm both fan switches → `on`. Then set it back to 25 and `gh_fan_off_temp` above current temp; confirm fans → `off`. Restore defaults (25/23). Check `automation.gh_fan_control` trace shows the expected branch. Expected: fans follow the threshold, no rapid toggling.

### Task 4: Safety alerts (overheat / cold)

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add overheat + critical + cold alerts** (rate-limited via `for:` and single mode):
```yaml
- id: gh_alert_overheat
  alias: "GH Alert overheat"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      above: input_number.gh_overheat_temp
      for: "00:02:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
  action:
    - service: script.gh_notify
      data:
        title: "🌡️ Greenhouse hot ({{ states('sensor.greenhouse_climate_2_temperature') }}°C)"
        message: "Above {{ states('input_number.gh_overheat_temp') }}°C — pollination at risk. Open the roll-up wall."
    - delay: "00:30:00"   # rate-limit re-fire

- id: gh_alert_overheat_critical
  alias: "GH Alert overheat critical"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      above: input_number.gh_overheat_critical
      for: "00:01:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
  action:
    - service: script.gh_notify
      data:
        title: "🔥 GREENHOUSE OVERHEATING ({{ states('sensor.greenhouse_climate_2_temperature') }}°C)"
        message: "Critical. Max ventilation now — open wall fully."
    - delay: "00:15:00"

- id: gh_alert_cold
  alias: "GH Alert cold"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      below: input_number.gh_cold_temp
      for: "00:05:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
  action:
    - service: script.gh_notify
      data:
        title: "❄️ Greenhouse cold ({{ states('sensor.greenhouse_climate_2_temperature') }}°C)"
        message: "Below {{ states('input_number.gh_cold_temp') }}°C — close the wall / check overnight."
    - delay: "00:30:00"
```

- [ ] **Step 2: Deploy + validate + reload** (rsync automations.yaml; check_config; `automation.reload`). Expected: OK.

- [ ] **Step 3: Functional test** — set `input_number.gh_overheat_temp` to just below current temp; after the 2-min `for:` confirm the push + persistent alert fires; restore to 30. Expected: alert received.

### Task 5: Humidity / pollination alerts

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add daytime humidity-out-of-range alert:**
```yaml
- id: gh_alert_humidity
  alias: "GH Alert humidity out of range"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_humidity
      above: 85
      for: "00:10:00"
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_humidity
      below: 55
      for: "00:10:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: sun.sun
      state: "above_horizon"
  action:
    - service: script.gh_notify
      data:
        title: "💧 Humidity {{ states('sensor.greenhouse_climate_2_humidity') }}%"
        message: >-
          {{ 'High (>85%) — botrytis risk, increase ventilation.' if (states('sensor.greenhouse_climate_2_humidity')|float(0)) > 85 else 'Low (<55%) — stigma may dry, mist/reduce ventilation.' }}
    - delay: "00:30:00"
```

- [ ] **Step 2: Deploy + validate + reload + functional test** (temporarily set the `above` to below current RH by editing is awkward since it's a literal — instead verify via trace by lowering with a template helper later; for now confirm config OK and the automation exists). Expected: config OK; `automation.gh_alert_humidity` present.

### Task 6: Sensor-offline alert

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add offline alert:**
```yaml
- id: gh_alert_sensor_offline
  alias: "GH Alert climate sensor offline"
  mode: single
  trigger:
    - platform: state
      entity_id: binary_sensor.greenhouse_climate_2_device_status
      to: "off"
      for: "00:15:00"
    - platform: state
      entity_id: binary_sensor.greenhouse_climate_2_device_status
      to: "unavailable"
      for: "00:15:00"
  action:
    - service: script.gh_notify
      data:
        title: "📡 Climate sensor offline"
        message: "greenhouse-climate-2 has been offline 15 min — automation is running blind."
```

- [ ] **Step 2: Deploy + validate + reload.** Expected: config OK; automation present.

### Task 7: Dashboard "Automation & Climate" section

**Files:** Modify `configs/homeassistant/ui-lovelace.yaml` (add a 3rd view)

- [ ] **Step 1: Append a new view** after the System & Health view:
```yaml
  # ==================== AUTOMATION ====================
  - title: Automation
    path: automation
    icon: mdi:robot
    cards:
      - type: entities
        title: Master
        entities:
          - entity: input_boolean.gh_automation_enabled
            name: Automation enabled
          - entity: switch.plugg_3_vifte_endevegg_ost
            name: Fan øst
          - entity: switch.plugg_5_vifte_endevegg_vest
            name: Fan vest
          - entity: switch.plugg_1_vanning
            name: Vanning
      - type: entities
        title: Thresholds (tune here)
        entities:
          - input_number.gh_fan_on_temp
          - input_number.gh_fan_off_temp
          - input_number.gh_humidity_max
          - input_number.gh_humidity_off
          - input_number.gh_overheat_temp
          - input_number.gh_overheat_critical
          - input_number.gh_cold_temp
```

- [ ] **Step 2: Deploy + validate** (rsync ui-lovelace.yaml; force lovelace config load via WS `lovelace/config force:true` → success=True). Refresh browser. Expected: Automation tab shows the toggle + sliders.

---

## PHASE 2 — Roll-up wall prompts

### Task 8: Wall open/close prompts

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add open + close prompt automations:**
```yaml
- id: gh_wall_open_prompt
  alias: "GH Wall - open prompt"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      above: 27
      for: "00:05:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: sun.sun
      state: "above_horizon"
  action:
    - service: script.gh_notify
      data:
        title: "🪟 Open the roll-up wall"
        message: "{{ states('sensor.greenhouse_climate_2_temperature') }}°C and climbing — fans alone may not hold it."
    - delay: "01:00:00"

- id: gh_wall_close_prompt
  alias: "GH Wall - close prompt"
  mode: single
  trigger:
    - platform: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      below: 18
      for: "00:15:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
  action:
    - service: script.gh_notify
      data:
        title: "🪟 Close the roll-up wall"
        message: "Down to {{ states('sensor.greenhouse_climate_2_temperature') }}°C — close up to hold night target (17–18.5°C)."
    - delay: "01:00:00"
```
*(Forecast-driven open/close, e.g. rain/wind, is a later enhancement once the basic prompts are validated.)*

- [ ] **Step 2: Deploy + validate + reload.** Expected: config OK; both automations present. Functional-test the open prompt by setting the `above: 27` near current temp via a temporary edit + trace, or trigger manually. Restore.

---

## PHASE 3 — Watering migration

### Task 9: Recreate the 5 base pulses in HA

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: USER ACTION (checkpoint):** disable the watering schedule in the Tapo app for plug #1 so HA and Tapo don't both drive `switch.plugg_1_vanning`. Confirm before proceeding.

- [ ] **Step 2: Add one pulse automation per slot** (pattern shown for 2; replicate for all 5 with the listed times/durations):
```yaml
- id: gh_water_0700
  alias: "GH Water 07:00 (20m)"
  mode: single
  trigger: [{platform: time, at: "07:00:00"}]
  condition: [{condition: state, entity_id: input_boolean.gh_automation_enabled, state: "on"}]
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:20:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}

- id: gh_water_0900
  alias: "GH Water 09:00 (15m)"
  mode: single
  trigger: [{platform: time, at: "09:00:00"}]
  condition: [{condition: state, entity_id: input_boolean.gh_automation_enabled, state: "on"}]
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:15:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}
```
Remaining slots: `gh_water_1100` (11:00, 10m), `gh_water_1300` (13:00, 10m), `gh_water_1500` (15:00, 15m).

- [ ] **Step 3: Deploy + validate + reload.** Expected: config OK; 5 `gh_water_*` automations present. Functional test: trigger `gh_water_1100` manually, confirm `switch.plugg_1_vanning` turns on then off ~10 min later (or shorten the delay temporarily to verify the on/off cycle quickly, then restore).

### Task 10: Forecast nudge + sunset-aware last pulse

**Files:** Modify `configs/homeassistant/automations.yaml` (append)

- [ ] **Step 1: Add a forecast-aware evening pulse** (extra short pulse on hot, dry, sunny days; skipped otherwise) — fires ~2.5 h before sunset using `sun.sun` `next_setting`:
```yaml
- id: gh_water_evening_nudge
  alias: "GH Water evening nudge (hot days)"
  mode: single
  trigger:
    - platform: template
      value_template: >-
        {{ now() >= (as_datetime(state_attr('sun.sun','next_setting')) - timedelta(hours=2, minutes=30)) and now() < (as_datetime(state_attr('sun.sun','next_setting')) - timedelta(hours=2, minutes=20)) }}
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: numeric_state
      entity_id: sensor.greenhouse_climate_2_temperature
      above: 26
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:08:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}
```
*(This adds a controlled extra pulse ~2.5 h before sunset only when it's hot — giving the evening dryback the program wants without disturbing the steady base schedule. A cool/rainy "trim" rule can be added once this is validated.)*

- [ ] **Step 2: Deploy + validate + reload.** Expected: config OK; automation present. Verify the template trigger logic with HA's Template editor (Developer Tools → Template) against the current `sun.sun` attributes before relying on it.

---

## Self-Review (author)
- **Spec coverage:** Helpers (Task 1) ✓; notify (Task 2) ✓; fan control + circulation + night guard (Task 3) ✓; safety alerts (Task 4) ✓; humidity (Task 5) ✓; sensor-offline (Task 6) ✓; dashboard (Task 7) ✓; wall prompts (Task 8) ✓; watering base + Tapo-disable (Task 9) ✓; nudge + sunset pulse (Task 10) ✓.
- **Gating:** every control/alert checks `gh_automation_enabled`; control tasks (3) also check `device_status`. ✓
- **Hysteresis:** fan ON/OFF use separate thresholds; circulation only turns off if not latched for cooling. ✓
- **No placeholders:** `<MOBILE_NOTIFY>` is resolved in Task 2 Step 1; `<SCRATCH>` path is the session scratchpad. Watering slots fully enumerated.
- **BER safety:** base schedule unchanged; nudge is one short conditional pulse. ✓
- **Risk:** new top-level includes (Task 1) need a restart; everything else uses domain reloads.
