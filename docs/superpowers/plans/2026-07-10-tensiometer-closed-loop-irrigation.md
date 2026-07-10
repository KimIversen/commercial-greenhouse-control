# Tensiometer Closed-Loop Irrigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Water the greenhouse from live soil-water tension (mild-generative band), with the existing time schedule kept only as a dead-sensor fallback.

**Architecture:** A single Home Assistant automation (`gh_water_tension_loop`) pulses `switch.greenhouse_6_vanning` for a fixed dose when average tension crosses an on-setpoint (or the drier probe hits a safety cap), then a min-interval lock covers the tensiometer lag. All numbers are `input_number`/`input_datetime` helpers so they tune from the dashboard. The 07/10/12 scheduled pulses gain a condition so they fire only when tension is unavailable or the loop is off. Ships behind a master toggle (OFF) for a verify-first rollout.

**Tech Stack:** Home Assistant YAML (automations, template conditions, input helpers), Lovelace YAML dashboard. No new integrations. Deploy = `rsync` to the server + HA restart.

## Global Constraints

- Pump switch: `switch.greenhouse_6_vanning`. Tension: `sensor.greenhouse_tensiometer_average_kpa`, `sensor.greenhouse_tensiometer_1_kpa` (ch1 = drier/safety), `sensor.greenhouse_tensiometer_2_kpa`.
- All new entities are prefixed `gh_`. Helpers follow existing file conventions exactly (bare-key in `sensors/*.yaml`; domain-keyed in the package).
- Two pre-existing master gates must both be `on` for any HA watering: `input_boolean.gh_automation_enabled`, `input_boolean.gh_watering_ha_enabled`. The loop adds a third: `input_boolean.gh_watering_closedloop_enabled`.
- Setpoint defaults (balanced band, from the approved spec): on 30 kPa · ch1 cap 40 · off 12 · dose 13 min · wait 30 min · daily cap 90 min · window 06:00–18:00.
- **Deploy constraint:** Tasks 1–5 are pure local authoring + commits and can be done anywhere. **Task 6 requires being on the greenhouse LAN** (SSH to `greenhouse` / 192.168.10.107). Ship with the closed-loop toggle **OFF**.
- Local YAML syntax check (no custom tags in these files): `python3 -c "import yaml; yaml.safe_load(open('<file>')); print('OK')"`. Full HA schema validation happens in Task 6.
- Commit on branch `greenhouse-automation-2026-06-28`. End commit messages with the repo's Co-Authored-By trailer.

---

### Task 1: Tunable helper entities

**Files:**
- Modify: `configs/homeassistant/sensors/automation_numbers.yaml` (append)
- Modify: `configs/homeassistant/sensors/automation_booleans.yaml` (append)
- Modify: `configs/homeassistant/packages/greenhouse_metrics.yaml` (extend the existing `input_datetime:` block, lines 1–3)

**Interfaces:**
- Produces (consumed by Tasks 2–6): `input_boolean.gh_watering_closedloop_enabled`; `input_number.gh_tension_on|gh_tension_off|gh_tension_ch1_cap|gh_pulse_minutes|gh_pulse_wait_minutes|gh_water_daily_cap_minutes|gh_water_today_minutes`; `input_datetime.gh_last_pulse_end|gh_water_window_start|gh_water_window_end`.

- [ ] **Step 1: Append the input_number helpers**

Append to `configs/homeassistant/sensors/automation_numbers.yaml`:

```yaml

gh_tension_on:
  name: "Tension: water above"
  min: 15
  max: 45
  step: 1
  initial: 30
  unit_of_measurement: "kPa"
  icon: mdi:gauge

gh_tension_off:
  name: "Tension: satisfied at/below"
  min: 5
  max: 25
  step: 1
  initial: 12
  unit_of_measurement: "kPa"
  icon: mdi:gauge-low

gh_tension_ch1_cap:
  name: "Tension: ch1 safety cap"
  min: 25
  max: 55
  step: 1
  initial: 40
  unit_of_measurement: "kPa"
  icon: mdi:gauge-full

gh_pulse_minutes:
  name: "Pulse length"
  min: 3
  max: 25
  step: 1
  initial: 13
  unit_of_measurement: "min"
  icon: mdi:timer

gh_pulse_wait_minutes:
  name: "Wait between pulses"
  min: 10
  max: 90
  step: 5
  initial: 30
  unit_of_measurement: "min"
  icon: mdi:timer-sand

gh_water_daily_cap_minutes:
  name: "Daily water cap"
  min: 20
  max: 180
  step: 5
  initial: 90
  unit_of_measurement: "min"
  icon: mdi:water-alert

gh_water_today_minutes:
  name: "Water minutes today"
  min: 0
  max: 300
  step: 1
  unit_of_measurement: "min"
  icon: mdi:water-check
```

Note: `gh_water_today_minutes` deliberately has **no** `initial` so it restores its value across an HA restart (the midnight reset in Task 2 zeroes it daily). The setpoints have `initial` so a restart always returns to safe defaults; a tuning change persists until the next restart (to make a tuning permanent, edit the `initial` here).

- [ ] **Step 2: Append the input_boolean toggle**

Append to `configs/homeassistant/sensors/automation_booleans.yaml`:

```yaml

gh_watering_closedloop_enabled:
  name: "Watering: tensiometer closed-loop"
  icon: mdi:valve
```

- [ ] **Step 3: Add the input_datetime helpers to the package**

In `configs/homeassistant/packages/greenhouse_metrics.yaml`, the file begins with:

```yaml
input_datetime:
  gh_watering_started: {name: "Watering started", has_date: true, has_time: true}
  gh_last_watering: {name: "Last watering", has_date: true, has_time: true}
```

Add three lines so it becomes:

```yaml
input_datetime:
  gh_watering_started: {name: "Watering started", has_date: true, has_time: true}
  gh_last_watering: {name: "Last watering", has_date: true, has_time: true}
  gh_last_pulse_end: {name: "Last pulse ended", has_date: true, has_time: true}
  gh_water_window_start: {name: "Water window start", has_time: true, initial: "06:00:00"}
  gh_water_window_end: {name: "Water window end", has_time: true, initial: "18:00:00"}
```

- [ ] **Step 4: Local syntax check (all three files)**

Run:
```bash
for f in sensors/automation_numbers.yaml sensors/automation_booleans.yaml packages/greenhouse_metrics.yaml; do
  python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/$f')); print('OK $f')"
done
```
Expected: three `OK ...` lines, no traceback.

- [ ] **Step 5: Commit**

```bash
git add configs/homeassistant/sensors/automation_numbers.yaml configs/homeassistant/sensors/automation_booleans.yaml configs/homeassistant/packages/greenhouse_metrics.yaml
git commit -m "feat(watering): tunable helpers for tensiometer closed-loop"
```

---

### Task 2: Daily-cap bookkeeping + last-pulse-end tracking

Adds the midnight counter reset and extends the existing `gh_watering_tracker` so that **every** pump-off (loop, schedule, or manual) records when it ended and adds its minutes to today's total. Doing the bookkeeping in the tracker keeps the loop automation (Task 3) clean.

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (add `gh_water_daily_reset`; extend the `stopped` branch of `gh_watering_tracker`)

**Interfaces:**
- Consumes: `input_datetime.gh_watering_started` (existing), `input_number.gh_water_today_minutes`, `input_datetime.gh_last_pulse_end` (Task 1).
- Produces (consumed by Task 3): a maintained `input_datetime.gh_last_pulse_end` (set on every pump-off) and `input_number.gh_water_today_minutes` (running daily total).

- [ ] **Step 1: Add the daily-reset automation**

Append to `configs/homeassistant/automations.yaml`:

```yaml

- id: gh_water_daily_reset
  alias: "GH Water - reset daily counter"
  mode: single
  trigger:
    - platform: time
      at: "00:00:00"
  action:
    - service: input_number.set_value
      target: {entity_id: input_number.gh_water_today_minutes}
      data: {value: 0}
```

- [ ] **Step 2: Extend the tracker's `stopped` branch**

In `configs/homeassistant/automations.yaml`, the `gh_watering_tracker` automation's `stopped` branch currently is:

```yaml
        - conditions: "{{ trigger.id == 'stopped' }}"
          sequence:
            - service: input_datetime.set_datetime
              target: {entity_id: input_datetime.gh_last_watering}
              data: {datetime: "{{ states('input_datetime.gh_watering_started') }}"}
            - service: input_number.set_value
              target: {entity_id: input_number.gh_last_watering_minutes}
              data:
                value: >-
                  {{ ((now().timestamp() - as_timestamp(states('input_datetime.gh_watering_started'))) / 60) | round(0) }}
```

Replace it with (adds the two new services at the end):

```yaml
        - conditions: "{{ trigger.id == 'stopped' }}"
          sequence:
            - service: input_datetime.set_datetime
              target: {entity_id: input_datetime.gh_last_watering}
              data: {datetime: "{{ states('input_datetime.gh_watering_started') }}"}
            - service: input_number.set_value
              target: {entity_id: input_number.gh_last_watering_minutes}
              data:
                value: >-
                  {{ ((now().timestamp() - as_timestamp(states('input_datetime.gh_watering_started'))) / 60) | round(0) }}
            - service: input_datetime.set_datetime
              target: {entity_id: input_datetime.gh_last_pulse_end}
              data: {datetime: "{{ now().strftime('%Y-%m-%d %H:%M:%S') }}"}
            - service: input_number.set_value
              target: {entity_id: input_number.gh_water_today_minutes}
              data:
                value: >-
                  {{ (states('input_number.gh_water_today_minutes') | float(0))
                     + ((now().timestamp() - as_timestamp(states('input_datetime.gh_watering_started'))) / 60) | round(1) }}
```

- [ ] **Step 3: Local syntax check**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/automations.yaml')); print('OK')"
```
Expected: `OK`.

- [ ] **Step 4: Deferred deploy-time verification (record for Task 6)**

After deploy, do a manual 1-min pump toggle, then in Developer Tools → Template confirm `input_number.gh_water_today_minutes` increased by ~1 and `input_datetime.gh_last_pulse_end` shows "now". (Runs in Task 6.)

- [ ] **Step 5: Commit**

```bash
git add configs/homeassistant/automations.yaml
git commit -m "feat(watering): daily-cap counter + last-pulse-end tracking"
```

---

### Task 3: Closed-loop controller automation

The core. Evaluated every 5 min (and immediately when avg crosses the on-setpoint); fires one dose only when all guards pass.

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (add `gh_water_tension_loop`)

**Interfaces:**
- Consumes: all Task-1 helpers; `input_datetime.gh_last_pulse_end` maintained by Task 2; `switch.greenhouse_6_vanning`; the tension sensors.
- Produces: pump pulses. (No new entities; the tracker in Task 2 records the aftermath.)

- [ ] **Step 1: Add the controller automation**

Append to `configs/homeassistant/automations.yaml`:

```yaml

- id: gh_water_tension_loop
  alias: "GH Water - tensiometer closed loop"
  mode: single
  max_exceeded: silent
  trigger:
    - platform: time_pattern
      minutes: "/5"
    - platform: numeric_state
      entity_id: sensor.greenhouse_tensiometer_average_kpa
      above: input_number.gh_tension_on
  condition:
    # --- master gates ---
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: input_boolean.gh_watering_ha_enabled
      state: "on"
    - condition: state
      entity_id: input_boolean.gh_watering_closedloop_enabled
      state: "on"
    # --- sensor valid (covers device-offline AND fault-guard NaN) ---
    - condition: template
      value_template: "{{ states('sensor.greenhouse_tensiometer_average_kpa') not in ['unavailable','unknown'] }}"
    # --- inside the daytime window ---
    - condition: template
      value_template: >-
        {{ today_at(states('input_datetime.gh_water_window_start')) <= now()
           <= today_at(states('input_datetime.gh_water_window_end')) }}
    # --- min interval since last pulse ended (covers tensiometer lag) ---
    - condition: template
      value_template: >-
        {{ (now().timestamp() - (state_attr('input_datetime.gh_last_pulse_end','timestamp') | float(0)))
           > (states('input_number.gh_pulse_wait_minutes') | float(30)) * 60 }}
    # --- tension trip: avg over on-setpoint OR drier probe over cap; and not already wet ---
    - condition: template
      value_template: >-
        {% set avg = states('sensor.greenhouse_tensiometer_average_kpa') | float(0) %}
        {% set ch1 = states('sensor.greenhouse_tensiometer_1_kpa') | float(0) %}
        {% set on = states('input_number.gh_tension_on') | float(30) %}
        {% set off = states('input_number.gh_tension_off') | float(12) %}
        {% set cap = states('input_number.gh_tension_ch1_cap') | float(40) %}
        {{ (avg >= on or ch1 >= cap) and avg > off }}
    # --- under the daily runtime cap ---
    - condition: template
      value_template: >-
        {{ (states('input_number.gh_water_today_minutes') | float(0))
           + (states('input_number.gh_pulse_minutes') | float(13))
           <= (states('input_number.gh_water_daily_cap_minutes') | float(90)) }}
  action:
    - service: switch.turn_on
      target: {entity_id: switch.greenhouse_6_vanning}
    - delay:
        minutes: "{{ states('input_number.gh_pulse_minutes') | int(13) }}"
    - service: switch.turn_off
      target: {entity_id: switch.greenhouse_6_vanning}
```

Why these choices: `mode: single` + `max_exceeded: silent` means a trigger during the 13-min dose is ignored (no overlap). The min-interval guard reads `gh_last_pulse_end` (set by the Task-2 tracker on pump-off), so after a dose the loop is locked out for `gh_pulse_wait_minutes` — this is the "dose then wait" that respects the ~20–30 min tension lag and prevents overshoot. `avg > off` skips pulsing when already wet.

- [ ] **Step 2: Local syntax check**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/automations.yaml')); print('OK')"
```
Expected: `OK`.

- [ ] **Step 3: Deferred deploy-time verification (record for Task 6)**

Paste this into Developer Tools → Template on the server and confirm each sub-condition matches live values (this is the "shadow" check before enabling):

```jinja
{% set avg = states('sensor.greenhouse_tensiometer_average_kpa') | float(0) %}
{% set ch1 = states('sensor.greenhouse_tensiometer_1_kpa') | float(0) %}
{% set on = states('input_number.gh_tension_on') | float(30) %}
{% set off = states('input_number.gh_tension_off') | float(12) %}
{% set cap = states('input_number.gh_tension_ch1_cap') | float(40) %}
avg={{ avg }} ch1={{ ch1 }} on={{ on }} off={{ off }} cap={{ cap }}
valid={{ states('sensor.greenhouse_tensiometer_average_kpa') not in ['unavailable','unknown'] }}
in_window={{ today_at(states('input_datetime.gh_water_window_start')) <= now() <= today_at(states('input_datetime.gh_water_window_end')) }}
interval_ok={{ (now().timestamp() - (state_attr('input_datetime.gh_last_pulse_end','timestamp') | float(0))) > (states('input_number.gh_pulse_wait_minutes') | float(30))*60 }}
tension_trip={{ (avg >= on or ch1 >= cap) and avg > off }}
under_cap={{ (states('input_number.gh_water_today_minutes')|float(0)) + (states('input_number.gh_pulse_minutes')|float(13)) <= (states('input_number.gh_water_daily_cap_minutes')|float(90)) }}
```

- [ ] **Step 4: Commit**

```bash
git add configs/homeassistant/automations.yaml
git commit -m "feat(watering): tensiometer closed-loop controller automation"
```

---

### Task 4: Backup-schedule gating + watchdog tighten

Makes the three scheduled pulses dormant while the loop is healthy, and tightens the stuck-pump watchdog to the new max dose.

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (`gh_water_0700`, `gh_water_1000`, `gh_water_1200`, `gh_water_watchdog`)

**Interfaces:**
- Consumes: `input_boolean.gh_watering_closedloop_enabled`, `sensor.greenhouse_tensiometer_average_kpa`.

- [ ] **Step 1: Add the backup condition to each scheduled pulse**

In `configs/homeassistant/automations.yaml`, each of `gh_water_0700`, `gh_water_1000`, `gh_water_1200` currently ends its `condition:` list with the `gh_watering_ha_enabled` state check. Append this **fourth** condition to **each** of the three automations' `condition:` list:

```yaml
    - condition: template
      value_template: >-
        {{ is_state('input_boolean.gh_watering_closedloop_enabled','off')
           or states('sensor.greenhouse_tensiometer_average_kpa') in ['unavailable','unknown'] }}
```

Result: a scheduled pulse fires only when the loop is off **or** tension is unreadable. When the loop is on and sensors are healthy, all three stay dormant.

- [ ] **Step 2: Tighten the watchdog**

In `gh_water_watchdog`, change the trigger `for:` from `"00:22:00"` to `"00:16:00"`:

```yaml
  trigger:
    - platform: state
      entity_id: switch.greenhouse_6_vanning
      to: "on"
      for: "00:16:00"
```

- [ ] **Step 3: Local syntax check**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/automations.yaml')); print('OK')"
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add configs/homeassistant/automations.yaml
git commit -m "feat(watering): schedule becomes dead-sensor backup; watchdog 22->16m"
```

---

### Task 5: Dashboard controls & observability

**Files:**
- Modify: `configs/homeassistant/ui-lovelace.yaml` (add one `entities` card in the same view as the existing `Thresholds (tune here)` card)

- [ ] **Step 1: Add the control card**

In `configs/homeassistant/ui-lovelace.yaml`, add this card as a new sibling immediately after the `Thresholds (tune here)` card (the automation/Master control view):

```yaml
      - type: entities
        title: "Watering – tensiometer loop"
        entities:
          - entity: input_boolean.gh_watering_closedloop_enabled
            name: "Closed-loop enabled"
          - entity: sensor.greenhouse_tensiometer_average_kpa
            name: "Tension avg"
          - entity: sensor.greenhouse_tensiometer_1_kpa
            name: "Tension ch1 (drier)"
          - type: divider
          - input_number.gh_tension_on
          - input_number.gh_tension_ch1_cap
          - input_number.gh_tension_off
          - input_number.gh_pulse_minutes
          - input_number.gh_pulse_wait_minutes
          - input_number.gh_water_daily_cap_minutes
          - type: divider
          - entity: input_number.gh_water_today_minutes
            name: "Water minutes today"
          - entity: input_datetime.gh_last_pulse_end
            name: "Last pulse ended"
          - entity: switch.greenhouse_6_vanning
            name: "Pump (Vanning #6)"
```

- [ ] **Step 2: Local syntax check**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/ui-lovelace.yaml')); print('OK')"
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add configs/homeassistant/ui-lovelace.yaml
git commit -m "feat(watering): dashboard card for closed-loop controls"
```

---

### Task 6: Deploy, validate, verify, and enable (LAN ONLY)

Requires being on the greenhouse LAN. Ships with the loop OFF; you enable it only after the checks pass.

**Files:** none (deploy + verify)

- [ ] **Step 1: Rsync all changed config to the server**

```bash
RSH="ssh -i $HOME/.ssh/{bitbucket_mb_air_15} -o IdentitiesOnly=yes"
DEST="greenhouse:/opt/greenhouse/config/homeassistant"
rsync -avz -e "$RSH" configs/homeassistant/sensors/automation_numbers.yaml   "$DEST/sensors/automation_numbers.yaml"
rsync -avz -e "$RSH" configs/homeassistant/sensors/automation_booleans.yaml  "$DEST/sensors/automation_booleans.yaml"
rsync -avz -e "$RSH" configs/homeassistant/packages/greenhouse_metrics.yaml  "$DEST/packages/greenhouse_metrics.yaml"
rsync -avz -e "$RSH" configs/homeassistant/automations.yaml                  "$DEST/automations.yaml"
rsync -avz -e "$RSH" configs/homeassistant/ui-lovelace.yaml                  "$DEST/ui-lovelace.yaml"
```

- [ ] **Step 2: HA config check**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  "docker exec greenhouse_homeassistant hass --script check_config -c /config" 2>&1 | tail -20
```
Expected: ends without `ERROR`/`Invalid config`. (Alternative: Developer Tools → YAML → Check Configuration.)

- [ ] **Step 3: Restart HA to load the new package helpers**

New `input_datetime` (package) and input helpers load cleanly on restart:
```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  "cd /opt/greenhouse && docker compose restart homeassistant"
```
Wait ~60 s, then confirm the new entities exist (Developer Tools → States, filter `gh_tension`).

- [ ] **Step 4: Confirm loop is OFF and schedule still covers**

In Developer Tools → States: `input_boolean.gh_watering_closedloop_enabled` should be `off` (its default). With it off, the Task-4 backup condition is true, so `gh_water_0700/1000/1200` still water normally. Good — nothing changed operationally yet.

- [ ] **Step 5: Shadow-verify the decision logic**

Paste the Task 3 Step 3 template into Developer Tools → Template. Confirm each line matches reality (e.g. `valid=True`, `in_window` correct for the current time, `tension_trip` matches whether avg is genuinely above the on-setpoint). Fix any setpoint via the dashboard card if a value looks wrong. This is the pre-enable "shadow" gate.

- [ ] **Step 6: Acceptance test — sensor-death fallback**

1. Note `sensor.greenhouse_tensiometer_average_kpa` reads a number.
2. Cut the tensiometer 5 V supply (pull the battery). Wait ~5 min (8-sample moving average drains).
3. Confirm avg → `unavailable` (firmware fault-guard).
4. Confirm the loop's `valid` condition is now false (Template line `valid=False`), so the loop would stand down.
5. Confirm the backup condition is now true (`states(...)=='unavailable'`), so the next scheduled pulse would fire.
6. Restore power; confirm avg returns to a number within ~2 min.

- [ ] **Step 7: Enable the loop and monitor the first day**

Flip `input_boolean.gh_watering_closedloop_enabled` ON (dashboard). Then watch:
- Settings → Automations → "GH Water - tensiometer closed loop" → **Traces**: each run shows which condition stopped it or that it pulsed.
- Logbook filtered to `switch.greenhouse_6_vanning`: pulses should appear when avg ≥ 30 (or ch1 ≥ 40), spaced ≥30 min, none outside 06:00–18:00, daily total ≤ 90 min.
- Tension curve should oscillate within ~10–32 kPa; mornings should reset to <12 kPa.

- [ ] **Step 8: Commit any setpoint tweaks**

If monitoring prompts a setpoint change, edit the `initial:` in `sensors/automation_numbers.yaml` (or the window in the package), re-run Task 6 Steps 1–3, then:
```bash
git add -A configs/homeassistant/
git commit -m "tune(watering): closed-loop setpoints after first-day observation"
```

---

## Rollback

Turn `input_boolean.gh_watering_closedloop_enabled` **off** → the backup condition (Task 4) immediately restores pure-schedule watering. To fully remove: `git revert` the Task 1–5 commits and re-run Task 6 Steps 1–3.

## Open items (not in scope; track for later)

- `sensor.gh_next_watering` (in `packages/greenhouse_metrics.yaml`) still hardcodes the **old 5-pulse** schedule and is misleading once the loop runs — refresh or retire it in a follow-up.
- `gh_water_window_end` is a fixed 18:00; Norway sunset drifts fast toward autumn. Future: make it `sunset − 3 h` dynamically.
- After ~1 week, revisit the 13-min dose and the ~10 kPa ch1/ch2 divergence (reposition a probe?).
