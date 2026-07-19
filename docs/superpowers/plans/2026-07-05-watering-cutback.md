# Watering Cutback (Tapo→HA + leaner schedule) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut daily watering ~65% and move the pump under sole HA control, replacing the five-pulse regime with three morning-weighted pulses (07:00/10:00/12:00 → 10/8/7 min) so the saturated pots (~5 kPa) get a long daily dry-back.

**Architecture:** Edit the dormant `gh_water_*` automations in `configs/homeassistant/automations.yaml` down to three pulses, deploy via `make deploy-ha` (watering stays gated OFF, so the deploy changes nothing live), then perform a guarded cutover — user disables the Tapo app schedule, then `input_boolean.gh_watering_ha_enabled` is switched ON — and verify behavior from the HA recorder.

**Tech Stack:** Home Assistant YAML automations, Tapo smart plug (`switch.plugg_1_vanning`), MariaDB recorder, Makefile/rsync/SSH deploy, ESPHome TX-E tensiometers (monitor only).

## Global Constraints

- Every watering pulse MUST be gated by BOTH `input_boolean.gh_automation_enabled` AND `input_boolean.gh_watering_ha_enabled` (state `"on"`), exactly as the existing pulses are.
- Target actuator is `switch.plugg_1_vanning` and nothing else.
- **Cutover ordering is mandatory:** the Tapo app daytime schedule MUST be disabled BEFORE `gh_watering_ha_enabled` is turned ON — otherwise both systems water the same pump (double dose).
- Keep `gh_water_watchdog` (force-off after 22 min) and `gh_watering_tracker` unchanged.
- Tensiometer stays **monitor-only** this phase — no automation may read `sensor.greenhouse_tensiometer_*` for control.
- Change must be reversible same-day: turning `gh_watering_ha_enabled` OFF fully stops HA watering.
- Server access: host alias `greenhouse` (192.168.10.107), key `~/.ssh/{bitbucket_mb_air_15}` (`-o IdentitiesOnly=yes`). Recorder is the `greenhouse_mariadb` container, DB `homeassistant`.

---

### Task 1: Reduce the watering automations to three pulses

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (the `# TASK 9: BASE WATERING PULSES` block through the end of the `# TASK 10: EVENING NUDGE` block — currently lines ~245–371)

**Interfaces:**
- Consumes: `input_boolean.gh_automation_enabled`, `input_boolean.gh_watering_ha_enabled`, `switch.plugg_1_vanning` (all already exist).
- Produces: automations with ids `gh_water_0700`, `gh_water_1000`, `gh_water_1200` (replacing `gh_water_0700/0900/1100/1300/1500`); `gh_water_evening_nudge` deleted; `gh_water_watchdog` and `gh_watering_tracker` untouched.

- [ ] **Step 1: Confirm the current watering ids before editing**

Run:
```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
grep -nE '^- id: gh_water' configs/homeassistant/automations.yaml
```
Expected (5 pulses + nudge + watchdog + tracker):
```
- id: gh_water_0700
- id: gh_water_0900
- id: gh_water_1100
- id: gh_water_1300
- id: gh_water_1500
- id: gh_water_evening_nudge
- id: gh_water_watchdog
- id: gh_watering_tracker
```

- [ ] **Step 2: Replace the five pulses + the evening-nudge block**

Replace everything from the `# ==================== TASK 9: BASE WATERING PULSES ====================` line through the last line of the evening-nudge automation (the `gh_water_evening_nudge` block, ending at its final `target: {entity_id: switch.plugg_1_vanning}`) with exactly this — leaving `gh_water_watchdog` and everything after it in place:

```yaml
# ==================== TASK 9: BASE WATERING PULSES (leaner, cut 2026-07-05) ====================
# 3 morning-weighted pulses, ~25 min/day (was ~70). Nothing after 12:00 -> long
# afternoon/overnight dry-back. Tune durations by watching the tensiometer dry-back.

- id: gh_water_0700
  alias: "GH Water 07:00 (10m)"
  mode: single
  trigger:
    - platform: time
      at: "07:00:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: input_boolean.gh_watering_ha_enabled
      state: "on"
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:10:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}

- id: gh_water_1000
  alias: "GH Water 10:00 (8m)"
  mode: single
  trigger:
    - platform: time
      at: "10:00:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: input_boolean.gh_watering_ha_enabled
      state: "on"
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:08:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}

- id: gh_water_1200
  alias: "GH Water 12:00 (7m)"
  mode: single
  trigger:
    - platform: time
      at: "12:00:00"
  condition:
    - condition: state
      entity_id: input_boolean.gh_automation_enabled
      state: "on"
    - condition: state
      entity_id: input_boolean.gh_watering_ha_enabled
      state: "on"
  action:
    - service: switch.turn_on
      target: {entity_id: switch.plugg_1_vanning}
    - delay: "00:07:00"
    - service: switch.turn_off
      target: {entity_id: switch.plugg_1_vanning}
```

- [ ] **Step 3: Verify structure and ids parse correctly (local, tolerant of HA `!` tags)**

Run:
```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
python3 - <<'PY'
import yaml
class L(yaml.SafeLoader): pass
L.add_multi_constructor('!', lambda loader, suffix, node: None)
with open('configs/homeassistant/automations.yaml') as f:
    data = yaml.load(f, Loader=L)
assert isinstance(data, list), "automations.yaml must be a YAML list"
ids = [a.get('id') for a in data if isinstance(a, dict)]
water = [i for i in ids if i and i.startswith('gh_water')]
print("total automations:", len(data))
print("watering ids:", water)
assert water == ['gh_water_0700','gh_water_1000','gh_water_1200','gh_water_watchdog','gh_watering_tracker'], water
print("OK")
PY
```
Expected: ends with `watering ids: ['gh_water_0700', 'gh_water_1000', 'gh_water_1200', 'gh_water_watchdog', 'gh_watering_tracker']` then `OK`.

- [ ] **Step 4: Confirm no dangling references to the removed ids**

Run:
```bash
grep -rnE 'gh_water_0900|gh_water_1100|gh_water_1300|gh_water_1500|gh_water_evening_nudge' configs/ || echo "NONE — good"
```
Expected: `NONE — good`.

- [ ] **Step 5: Commit**

```bash
git add configs/homeassistant/automations.yaml
git commit -m "feat(watering): cut to 3 morning pulses (07/10/12, ~25min/day); drop evening nudge"
```

---

### Task 2: Deploy config to the server (safe — watering still gated OFF)

**Files:** none changed; deploys the Task 1 edit. Because `gh_watering_ha_enabled` is still OFF, this deploy does NOT change live watering — it only updates what *would* run once enabled.

**Interfaces:**
- Consumes: the committed `automations.yaml`.
- Produces: updated `/opt/greenhouse/config/homeassistant/automations.yaml` on the server + restarted `homeassistant` container with a valid config.

- [ ] **Step 1: Get explicit user go-ahead** — `make deploy-ha` restarts the live Home Assistant container. Confirm with the user before running (production action).

- [ ] **Step 2: Deploy HA config + restart**

Run:
```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
make deploy-ha
```
Expected: rsync summary, `Restarting Home Assistant...`, `Done.` with no rsync/SSH errors.

- [ ] **Step 3: Verify HA reloaded the config without errors**

Run:
```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  "cd /opt/greenhouse && docker compose logs --since 4m homeassistant 2>&1 | grep -iE 'invalid config|error.*automation|setup of automation|traceback' | head"
```
Expected: no `Invalid config` / automation setup errors. (Empty output, or only benign INFO lines, is a pass.)

- [ ] **Step 4: Confirm the three pulses are loaded and old ones are gone**

Run:
```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse 'bash -s' <<'EOF'
CID=greenhouse_mariadb
Q="SELECT entity_id FROM states_meta WHERE entity_id LIKE 'automation.gh_water%';"
docker exec -e Q="$Q" "$CID" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" homeassistant -N -e "$Q"' 2>/dev/null | sort
EOF
```
Expected to include `automation.gh_water_0700`, `automation.gh_water_1000`, `automation.gh_water_1200`, `automation.gh_water_watchdog`, `automation.gh_watering_tracker`. (Old `automation.gh_water_0900/1100/1300/1500/gh_water_evening_nudge` may linger as stale recorder rows but must NOT appear in HA's live automation list — if unsure, confirm on the dashboard Automations page that only the three pulses show.)

---

### Task 3: Guarded cutover — disable Tapo, then enable HA watering

**Files:** none. This flips runtime state only.

**Interfaces:**
- Consumes: deployed automations from Task 2.
- Produces: `input_boolean.gh_watering_ha_enabled = on`, Tapo schedule disabled — HA is the sole watering driver.

- [ ] **Step 1: USER disables the Tapo daytime schedule** — In the Tapo app, plug #1 (`Vanning`): delete/disable the `05:00/07:00/09:00/11:00/13:00` schedule. (Away Mode already off.) User confirms it's done. **Do not proceed until confirmed** — this ordering prevents double-watering.

- [ ] **Step 2: Enable HA watering** — User flips `input_boolean.gh_watering_ha_enabled` → ON on the dashboard "Automation" tab. (Alternatively, with an authorized HA token/service call, `input_boolean.turn_on` on that entity — but the user-driven dashboard toggle is preferred for a live actuator.)

- [ ] **Step 3: Verify exactly one source is armed** — Confirm `gh_automation_enabled` is ON and `gh_watering_ha_enabled` is ON, and that the Tapo schedule is gone. The next scheduled HA pulse (07:00/10:00/12:00) should be the only activation.

---

### Task 4: Behavioral verification + first-week tuning (operational)

**Files:** none. Verification + tuning against live data.

- [ ] **Step 1: After the first HA-driven day, pull the pump log and confirm the new pattern**

Run:
```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse 'bash -s' <<'EOF'
CID=greenhouse_mariadb
Q="SELECT FROM_UNIXTIME(s.last_updated_ts) t, s.state FROM states s JOIN states_meta m ON s.metadata_id=m.metadata_id WHERE m.entity_id='switch.plugg_1_vanning' AND s.last_updated_ts > UNIX_TIMESTAMP(NOW() - INTERVAL 28 HOUR) AND s.state IN ('on','off') ORDER BY s.last_updated_ts;"
docker exec -e Q="$Q" "$CID" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" homeassistant -N -e "$Q"' 2>/dev/null
EOF
```
Expected: `on` at ~07:00 (off ~07:10), ~10:00 (off ~10:08), ~12:00 (off ~12:07). **No** overnight or afternoon activations.

- [ ] **Step 2: Confirm the dry-back is appearing**

Run:
```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse 'bash -s' <<'EOF'
CID=greenhouse_mariadb
Q="SELECT FROM_UNIXTIME(s.last_updated_ts) t, s.state FROM states s JOIN states_meta m ON s.metadata_id=m.metadata_id WHERE m.entity_id='sensor.greenhouse_tensiometer_average_kpa' AND s.last_updated_ts > UNIX_TIMESTAMP(NOW() - INTERVAL 28 HOUR) AND s.state NOT IN ('unknown','unavailable') ORDER BY s.last_updated_ts;"
docker exec -e Q="$Q" "$CID" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" homeassistant -N -e "$Q"' 2>/dev/null | awk 'NR==1||NR%20==0'
EOF
```
Expected: avg kPa trends UP (drier) through afternoon/night vs. the flat ~5 kPa baseline — a daily saw-tooth, re-wet each morning.

- [ ] **Step 3: Tune (durations only, keep the 3-pulse shape)**
  - Still flat & wet near ~5 kPa → shorten pulses further (or add a one-off dry-down day).
  - Climbing too high/fast (wilt risk, or past the ~40–50 kPa guard from the parked design) → add minutes back (first fallback: 12/10/9 ≈ 31 min/day).
  - Re-run Task 1 Steps 2–5 + Task 2 for any duration change. **Do not** add a kPa control gate yet — that's Phase 2 after ~1–2 weeks of baseline.

---

## Notes / open items (from the spec, non-blocking)

- Emitter flow rate + plant/emitter count unconfirmed → the ≈0.8 L/plant/day figure is an estimate; confirm to firm up volume math.
- Check whether the pots free-drain; if not, saturation is accumulation and the dry-back will appear more slowly.
- Rollback anytime: `gh_watering_ha_enabled` → OFF (and/or re-enable Tapo).
