# Shelly 1PM Gen3 Plug Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repoint every watering and fan reference in Home Assistant from the three dead Tapo plugs to the newly installed Shelly 1PM Gen3 devices, fixing an inverted entity-ID mapping and adding a power-verified pump watchdog.

**Architecture:** Four local YAML tasks (pure authoring, nothing deployed) followed by a single deploy task that does config rsync → `check_config` → HA stop → offline entity-registry edit → HA start → verify. One restart total. The registry edit is done offline because HA rewrites `.storage` from memory on exit.

**Tech Stack:** Home Assistant YAML (automations, Lovelace, packages, input_number helpers), Shelly Gen3 local RPC API, Python 3 for the registry edit, rsync/SSH deploy, MariaDB recorder for verification.

## Global Constraints

- **Design spec:** `docs/superpowers/specs/2026-07-19-shelly-plug-migration-design.md` — read it before starting.
- **Entity mapping (exact, use verbatim):**
  - `switch.greenhouse_6_vanning` → `switch.greenhouse_shelly_watering`
  - `switch.plugg_3_vifte_endevegg_ost` → `switch.greenhouse_shelly_fan_east`
  - `switch.plugg_5_vifte_endevegg_vest` → `switch.greenhouse_shelly_fan_west`
- **The fan entity IDs are currently inverted.** `switch.greenhouse_shelly_fan_east` today belongs to device *Shelly - Fan West* (192.168.10.164). Task 5 renames it. Never assume the current slug matches the physical fan.
- **Device → IP:** Watering `.194`, Fan East `.187`, Fan West `.164`. Device IDs: watering `0f2cbfd9…`, east `3451abe7…`, west `a88f3281…`.
- **No pytest in this repo.** Verification is HA-native: `python3 -c "import yaml; yaml.safe_load(...)"` for syntax, `hass --script check_config` for schema, Developer Tools → Template for logic, automation traces for runtime.
- **SSH:** `ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse` — literal braces in the key filename. Plain `ssh greenhouse` is NOT authorized.
- **Deploy gotcha:** before rsyncing any single file, run a full-directory `rsync -n --itemize-changes` to catch other undeployed divergence.
- **Do not change** `input_boolean.gh_watering_closedloop_enabled` (stays off / shadow mode).
- Commit after every task.

---

### Task 1: Swap the three switch entity IDs across all config files

The mapping is 1:1 and unambiguous, so this is a mechanical global replace. 31 occurrences across 3 files.

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (10 fan refs, 12 watering refs, over 18 lines — several lines carry both fan entities)
- Modify: `configs/homeassistant/ui-lovelace.yaml` (switch refs only — the Plug Health card is Task 2)
- Modify: `configs/homeassistant/packages/greenhouse_metrics.yaml` (2 `history_stats` refs)

**Interfaces:**
- Produces: the three new `switch.greenhouse_shelly_*` entity IDs, referenced by every later task.

- [ ] **Step 1: Record the "before" reference counts**

Count **occurrences**, not matching lines — several lines carry both fan entities, so `grep -c` undercounts.

```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
PAT='switch\.greenhouse_6_vanning\|switch\.plugg_3_vifte_endevegg_ost\|switch\.plugg_5_vifte_endevegg_vest'
for f in configs/homeassistant/automations.yaml \
         configs/homeassistant/ui-lovelace.yaml \
         configs/homeassistant/packages/greenhouse_metrics.yaml; do
  echo "$f = $(grep -o "$PAT" "$f" | wc -l | tr -d ' ')"
done
```

Expected output (exact):
```
configs/homeassistant/automations.yaml = 22
configs/homeassistant/ui-lovelace.yaml = 7
configs/homeassistant/packages/greenhouse_metrics.yaml = 2
```

If these numbers differ, STOP — the files have drifted from the plan; re-read them before continuing.

Note the patterns are `switch.`-prefixed on purpose. The Plug Health card also contains
`binary_sensor.greenhouse_6_vanning_cloud_connection` and friends, which must **not** be caught by
the Task 1 replace — those entities have no Shelly equivalent and are removed wholesale in Task 2.

- [ ] **Step 2: Apply the replacement**

```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
for f in configs/homeassistant/automations.yaml \
         configs/homeassistant/ui-lovelace.yaml \
         configs/homeassistant/packages/greenhouse_metrics.yaml; do
  sed -i '' \
    -e 's/switch\.greenhouse_6_vanning/switch.greenhouse_shelly_watering/g' \
    -e 's/switch\.plugg_3_vifte_endevegg_ost/switch.greenhouse_shelly_fan_east/g' \
    -e 's/switch\.plugg_5_vifte_endevegg_vest/switch.greenhouse_shelly_fan_west/g' \
    "$f"
done
```

Note `sed -i ''` — BSD/macOS sed requires the empty backup argument.

- [ ] **Step 3: Verify zero old references remain and counts carried over**

```bash
grep -rn "switch\.greenhouse_6_vanning\|switch\.plugg_" configs/ ; echo "exit=$?"
```

Expected: no output, `exit=1` (grep found nothing).

The Tapo *diagnostic* entities (`binary_sensor.greenhouse_6_vanning_cloud_connection`,
`sensor.greenhouse_3_vifte_endevegg_signal_level`, …) are still present in `ui-lovelace.yaml` at
this point — that is correct, Task 2 removes them. Do not try to sed them away here; they have no
Shelly equivalent and need a rebuilt card, not a rename.

```bash
PAT='switch\.greenhouse_shelly_watering\|switch\.greenhouse_shelly_fan_east\|switch\.greenhouse_shelly_fan_west'
for f in configs/homeassistant/automations.yaml \
         configs/homeassistant/ui-lovelace.yaml \
         configs/homeassistant/packages/greenhouse_metrics.yaml; do
  echo "$f = $(grep -o "$PAT" "$f" | wc -l | tr -d ' ')"
done
```

Expected: `22`, `7`, `2` — the same counts as Step 1, now on the new entity IDs.

- [ ] **Step 4: Verify YAML still parses**

```bash
python3 -c "
import yaml,sys
for f in ['configs/homeassistant/automations.yaml','configs/homeassistant/ui-lovelace.yaml','configs/homeassistant/packages/greenhouse_metrics.yaml']:
    try:
        yaml.safe_load(open(f))
        print('OK', f)
    except Exception as e:
        print('FAIL', f, e); sys.exit(1)
"
```

Expected: three `OK` lines. (`ui-lovelace.yaml` may raise on the `!include` tag — if so, that is pre-existing and acceptable; confirm by running the same check on `git stash`'d original.)

- [ ] **Step 5: Confirm the east/west split landed on the right automations**

The fan-state check must read the **east** plug, matching the pre-migration behaviour:

```bash
grep -n "fans_on:\|entity_id: switch.greenhouse_shelly_fan" configs/homeassistant/automations.yaml
```

Expected: the `fans_on:` template and the `gh_fan_circulation` condition both reference `switch.greenhouse_shelly_fan_east`; the `turn_on`/`turn_off` targets list both `fan_east` and `fan_west`.

- [ ] **Step 6: Commit**

```bash
git add configs/homeassistant/automations.yaml configs/homeassistant/ui-lovelace.yaml configs/homeassistant/packages/greenhouse_metrics.yaml
git commit -m "refactor(ha): repoint watering + fan control from Tapo to Shelly plugs

The three Tapo plugs were physically replaced with Shelly 1PM Gen3 units
and now read unavailable. Swap all 22 entity references.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rebuild the Plug Health card and add plug power to the dashboard

The Tapo card used `cloud_connection` / `signal_level` / `overheated`, none of which exist on Shelly. Replace with Shelly's equivalents plus the power readings the 1PM provides.

**Files:**
- Modify: `configs/homeassistant/ui-lovelace.yaml` — Plug Health card (currently ~lines 79-101), and a new Plug Power card after the Controls card (~line 48)

**Interfaces:**
- Consumes: the switch entity IDs from Task 1.
- Produces: dashboard rows for `sensor.greenhouse_shelly_<role>_effekt`, `_signalstyrke`, `_temperatur`, `_spenning`. These entity IDs are created by the registry rename in Task 5 — until then they will render as "Entitet ikke funnet", which is expected.

- [ ] **Step 1: Replace the Plug Health card**

Find the card titled `Plug Health` and replace the whole card (from `- type: entities` through the last `Overheated` row) with:

```yaml
      - type: entities
        title: Plug Health
        entities:
          - type: section
            label: "Vanning"
          - entity: sensor.greenhouse_shelly_watering_signalstyrke
            name: "Signal"
          - entity: sensor.greenhouse_shelly_watering_temperatur
            name: "Temperatur"
          - entity: sensor.greenhouse_shelly_watering_spenning
            name: "Nettspenning"
          - entity: binary_sensor.greenhouse_shelly_watering_overheating
            name: "Overoppheting"
          - entity: binary_sensor.greenhouse_shelly_watering_overpowering
            name: "Overbelastning"
          - type: section
            label: "Vifte øst"
          - entity: sensor.greenhouse_shelly_fan_east_signalstyrke
            name: "Signal"
          - entity: sensor.greenhouse_shelly_fan_east_temperatur
            name: "Temperatur"
          - entity: sensor.greenhouse_shelly_fan_east_spenning
            name: "Nettspenning"
          - entity: binary_sensor.greenhouse_shelly_fan_east_overheating
            name: "Overoppheting"
          - entity: binary_sensor.greenhouse_shelly_fan_east_overpowering
            name: "Overbelastning"
          - type: section
            label: "Vifte vest"
          - entity: sensor.greenhouse_shelly_fan_west_signalstyrke
            name: "Signal"
          - entity: sensor.greenhouse_shelly_fan_west_temperatur
            name: "Temperatur"
          - entity: sensor.greenhouse_shelly_fan_west_spenning
            name: "Nettspenning"
          - entity: binary_sensor.greenhouse_shelly_fan_west_overheating
            name: "Overoppheting"
          - entity: binary_sensor.greenhouse_shelly_fan_west_overpowering
            name: "Overbelastning"
```

- [ ] **Step 2: Add a Plug Power card immediately after the Controls card**

The Controls card ends with the `Vifte endevegg vest` entry. Insert directly after it, at the same indentation as `- type: entities`:

```yaml
      # --- Live power draw (Shelly 1PM) ---
      - type: entities
        title: Plug Power
        show_header_toggle: false
        entities:
          - entity: sensor.greenhouse_shelly_watering_effekt
            name: "Vanning – pumpe"
            icon: mdi:water-pump
          - entity: sensor.greenhouse_shelly_fan_east_effekt
            name: "Vifte øst"
            icon: mdi:fan
          - entity: sensor.greenhouse_shelly_fan_west_effekt
            name: "Vifte vest"
            icon: mdi:fan
```

- [ ] **Step 3: Update the stale Controls card comment and entry names**

The Controls card is preceded by `# --- Controls (Tapo plugs) ---`. Change to `# --- Controls (Shelly 1PM plugs) ---`. Then update the three display names, which still carry Tapo plug numbers:

```yaml
          - entity: switch.greenhouse_shelly_watering
            name: "Vanning"
            icon: mdi:water
          - entity: switch.greenhouse_shelly_fan_east
            name: "Vifte endevegg øst"
            icon: mdi:fan
          - entity: switch.greenhouse_shelly_fan_west
            name: "Vifte endevegg vest"
            icon: mdi:fan
```

- [ ] **Step 4: Update the closed-loop card's pump label**

Find `name: "Pump (Vanning #6)"` and change to `name: "Pumpe (Vanning)"`.

- [ ] **Step 5: Verify no Tapo-era entity or label survives**

```bash
grep -n "cloud_connection\|signal_level\|overheated\|#6\|(#3)\|(#5)\|Tapo" configs/homeassistant/ui-lovelace.yaml ; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add configs/homeassistant/ui-lovelace.yaml
git commit -m "feat(dashboard): rebuild Plug Health on Shelly diagnostics, add Plug Power

Tapo's cloud_connection/signal_level/overheated have no Shelly analogue.
Replace with signal/temperature/voltage plus the overheating and
overpowering binary sensors, and surface live 1PM power draw.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Power-verified watering watchdog

A commanded relay and a dead pump are indistinguishable to HA today. The 1PM's power metering closes that gap. **Alert-only** — a flaky power reading must never cancel a legitimate pulse.

**Files:**
- Modify: `configs/homeassistant/sensors/automation_numbers.yaml` (append helper)
- Modify: `configs/homeassistant/automations.yaml` (fix stale watchdog text; append new automation)
- Modify: `configs/homeassistant/ui-lovelace.yaml` (expose the helper for tuning)

**Interfaces:**
- Consumes: `switch.greenhouse_shelly_watering` (Task 1), `sensor.greenhouse_shelly_watering_effekt` (Task 5 rename — already correctly named, no rename needed), `script.gh_notify` (existing; takes `title` and `message` in `data`).
- Produces: `input_number.gh_pump_min_watts`, automation id `gh_water_no_flow_alert`.

- [ ] **Step 1: Append the threshold helper**

Append to the end of `configs/homeassistant/sensors/automation_numbers.yaml` (flat mapping — no leading list dash):

```yaml

gh_pump_min_watts:
  name: "Pump min watts (flow check)"
  min: 0
  max: 300
  step: 5
  initial: 30
  unit_of_measurement: "W"
  icon: mdi:flash-alert
```

Default 30 W is derived from the measured pump draw of ~108 W steady (174 W inrush) — far below true draw, far above sensor noise.

- [ ] **Step 2: Fix the stale watchdog message**

In `configs/homeassistant/automations.yaml`, the `gh_water_watchdog` trigger fires at `00:16:00` but its message still says 22 minutes. Change:

```yaml
        message: "Vanning pump was on >22 min — forced off (possible stuck pulse after a restart)."
```

to:

```yaml
        message: "Vanning pump was on >16 min — forced off (possible stuck pulse after a restart)."
```

- [ ] **Step 3: Append the new automation**

Append to the end of `configs/homeassistant/automations.yaml`:

```yaml

- id: gh_water_no_flow_alert
  alias: "GH Watering no-flow alert (pump drawing no power)"
  mode: single
  trigger:
    - platform: state
      entity_id: switch.greenhouse_shelly_watering
      to: "on"
      for: "00:02:00"
  condition:
    # still on — guards against a pulse that ended during the settle window
    - condition: state
      entity_id: switch.greenhouse_shelly_watering
      state: "on"
    # power sensor must be reporting a real number; if it is unavailable we
    # cannot conclude anything, so stay silent rather than cry wolf
    - condition: template
      value_template: >-
        {{ states('sensor.greenhouse_shelly_watering_effekt')
           not in ['unavailable','unknown','none',''] }}
    - condition: template
      value_template: >-
        {{ (states('sensor.greenhouse_shelly_watering_effekt') | float(9999))
           < (states('input_number.gh_pump_min_watts') | float(30)) }}
  action:
    - service: script.gh_notify
      data:
        title: "🚱 Vanning: ingen strømtrekk"
        message: >-
          Pumpen er kommandert PÅ men trekker bare
          {{ states('sensor.greenhouse_shelly_watering_effekt') }} W
          (grense {{ states('input_number.gh_pump_min_watts') }} W).
          Sjekk pumpe, sikring og kobling — vanning kan ha stoppet.
```

Note the `float(9999)` default: if the state is somehow unparseable the comparison fails safe (no alert) rather than firing spuriously.

- [ ] **Step 4: Expose the helper on the Automation view**

In `configs/homeassistant/ui-lovelace.yaml`, find the `Watering – tensiometer loop` card and add after `- input_number.gh_water_daily_cap_minutes`:

```yaml
          - input_number.gh_pump_min_watts
```

- [ ] **Step 5: Verify YAML parses and the automation id is unique**

```bash
python3 -c "
import yaml
a = yaml.safe_load(open('configs/homeassistant/automations.yaml'))
ids = [x['id'] for x in a]
assert len(ids) == len(set(ids)), 'DUPLICATE automation id: %s' % [i for i in ids if ids.count(i)>1]
assert 'gh_water_no_flow_alert' in ids, 'new automation missing'
print('OK — %d automations, ids unique' % len(ids))
n = yaml.safe_load(open('configs/homeassistant/sensors/automation_numbers.yaml'))
assert 'gh_pump_min_watts' in n, 'helper missing'
print('OK — gh_pump_min_watts present, initial=%s' % n['gh_pump_min_watts']['initial'])
"
```

Expected:
```
OK — <N> automations, ids unique
OK — gh_pump_min_watts present, initial=30
```

- [ ] **Step 6: Verify the stale message is gone**

```bash
grep -n ">22 min" configs/homeassistant/automations.yaml ; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 7: Commit**

```bash
git add configs/homeassistant/automations.yaml configs/homeassistant/sensors/automation_numbers.yaml configs/homeassistant/ui-lovelace.yaml
git commit -m "feat(watering): power-verified no-flow alert on the pump

The Shelly 1PM meters real draw, so a commanded-but-dead pump is now
detectable — previously indistinguishable from a healthy pulse. Alert
only; a flaky reading must not be able to cancel a watering pulse.

Also corrects gh_water_watchdog's message, which still said 22 min after
the trigger was tightened to 16.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the network address table**

In the "Network Configuration" list, add after the `192.168.10.162` line:

```markdown
  - 192.168.10.164: Shelly - Fan West (Shelly 1PM Gen3, endwall fan west)
  - 192.168.10.187: Shelly - Fan East (Shelly 1PM Gen3, endwall fan east)
  - 192.168.10.194: Shelly - Watering (Shelly 1PM Gen3, irrigation pump)
```

- [ ] **Step 2: Add a Shelly section under "System Overview"**

Append to the end of the "### ESP32 Device Types" section:

```markdown
### Mains Switching (Shelly)
Three **Shelly 1PM Gen3** relays replaced the original TP-Link/Tapo plugs (2026-07-19).
Each provides local-API switching plus true power metering (W, A, V, Wh, device temperature).
Entities: `switch.greenhouse_shelly_watering`, `switch.greenhouse_shelly_fan_east`,
`switch.greenhouse_shelly_fan_west`.

**Entity-ID caveat:** `switch.greenhouse_shelly_fan_east` originally belonged to the *west*
unit — HA does not regenerate entity IDs when a device is renamed. This was corrected in the
entity registry on 2026-07-19. If a plug is ever replaced again, grep for the switch entity ID
**and** the device-name slug, and confirm the physical mapping by power draw before trusting a
slug.

Power metering enables `gh_water_no_flow_alert`, which detects a pump that is commanded on but
drawing no current — a failure previously invisible to HA.
```

- [ ] **Step 3: Verify no stale Tapo plug references remain in the doc**

```bash
grep -n -i "tapo\|plugg_" CLAUDE.md ; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document the Shelly 1PM Gen3 plugs and the entity-ID caveat

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Deploy — config rsync, registry rename, single restart

**This task touches production.** It stops Home Assistant. Get explicit user go-ahead before Step 4.

**Files:**
- Modify (remote): `/opt/greenhouse/config/homeassistant/{automations.yaml,ui-lovelace.yaml,packages/greenhouse_metrics.yaml,sensors/automation_numbers.yaml}`
- Modify (remote): `/config/.storage/core.entity_registry`
- Create (remote): a timestamped registry backup

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: live entity IDs `switch.greenhouse_shelly_fan_{east,west}` correctly bound to their physical fans, and enabled diagnostics `sensor.greenhouse_shelly_<role>_{signalstyrke,temperatur,spenning}`.

- [ ] **Step 1: Full-directory dry run to catch other undeployed divergence**

```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
rsync -avzn --itemize-changes \
  -e 'ssh -i '"$HOME"'/.ssh/{bitbucket_mb_air_15} -o IdentitiesOnly=yes' \
  configs/homeassistant/ greenhouse:/opt/greenhouse/config/homeassistant/
```

Expected: only the four files from Tasks 1-4 listed. If anything else appears, STOP and report it to the user before deploying — a previous session shipped `ui-lovelace.yaml` ahead of its helpers and broke the dashboard.

- [ ] **Step 2: Deploy the four files**

```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
for f in automations.yaml ui-lovelace.yaml packages/greenhouse_metrics.yaml sensors/automation_numbers.yaml; do
  rsync -avz -e 'ssh -i '"$HOME"'/.ssh/{bitbucket_mb_air_15} -o IdentitiesOnly=yes' \
    "configs/homeassistant/$f" "greenhouse:/opt/greenhouse/config/homeassistant/$f"
done
```

- [ ] **Step 3: Validate config while HA is still up**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  'docker exec greenhouse_homeassistant python -m homeassistant --script check_config -c /config; echo "EXIT=$?"'
```

Expected: `EXIT=0`. If non-zero, fix locally and redeploy before going further — do not stop HA with a broken config.

- [ ] **Step 4: Back up the entity registry and stop HA**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
  docker exec greenhouse_homeassistant sh -c "cp /config/.storage/core.entity_registry /config/.storage/core.entity_registry.bak-shelly-20260719" &&
  docker compose -f /opt/greenhouse/docker-compose.yml stop homeassistant &&
  echo STOPPED'
```

Expected: `STOPPED`. The backup must be taken **before** the stop so it captures the live state.

- [ ] **Step 5: Rewrite the registry offline**

Renames are computed in memory and written once, so ordering cannot cause a collision. The script validates uniqueness before writing and refuses to save otherwise.

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
docker run --rm -v /opt/greenhouse/config/homeassistant:/config python:3.12-alpine python - <<"PY"
import json

ROLES = {
    "Shelly - Watering": "watering",
    "Shelly - Fan East": "fan_east",
    "Shelly - Fan West": "fan_west",
}
ENABLE = {"signalstyrke", "temperatur", "spenning"}

dev = json.load(open("/config/.storage/core.device_registry"))
ent_path = "/config/.storage/core.entity_registry"
ent = json.load(open(ent_path))

# device_id -> role
dmap = {}
for d in dev["data"]["devices"]:
    name = d.get("name_by_user") or d.get("name")
    if name in ROLES:
        dmap[d["id"]] = ROLES[name]
assert len(dmap) == 3, "expected 3 Shelly devices, found %d" % len(dmap)

changes = []
for e in ent["data"]["entities"]:
    role = dmap.get(e.get("device_id"))
    if not role:
        continue
    domain, obj = e["entity_id"].split(".", 1)

    if obj.startswith("greenhouse_shelly_fan_east"):
        suffix = obj[len("greenhouse_shelly_fan_east"):]
        # the _2 collision suffix belongs only to the East device
        if role == "fan_east" and suffix.endswith("_2"):
            suffix = suffix[:-2]
    elif obj.startswith("greenhouse_shelly_watering"):
        suffix = obj[len("greenhouse_shelly_watering"):]
    elif obj.startswith("shelly1pmg3_"):
        # shelly1pmg3_<mac>_<metric>
        suffix = "_" + obj.split("_", 2)[2]
    else:
        print("SKIP (unrecognised):", e["entity_id"])
        continue

    new_id = "%s.greenhouse_shelly_%s%s" % (domain, role, suffix)
    metric = suffix.lstrip("_")
    if metric in ENABLE and e.get("disabled_by") is not None:
        e["disabled_by"] = None
        changes.append("ENABLE  " + new_id)
    if new_id != e["entity_id"]:
        changes.append("RENAME  %-58s -> %s" % (e["entity_id"], new_id))
        e["entity_id"] = new_id

# uniqueness gate — refuse to write a registry with collisions
all_ids = [e["entity_id"] for e in ent["data"]["entities"]]
dupes = {i for i in all_ids if all_ids.count(i) > 1}
assert not dupes, "COLLISION, aborting without writing: %s" % dupes

with open(ent_path, "w") as f:
    json.dump(ent, f)
print("\n".join(changes))
print("--- %d changes written, %d entities total, no collisions" % (len(changes), len(all_ids)))
PY'
```

Expected: a list of RENAME/ENABLE lines ending in `--- <N> changes written, ... no collisions`. Confirm the listing shows `switch.greenhouse_shelly_fan_east -> switch.greenhouse_shelly_fan_west` (the west unit shedding the wrong slug) and `switch.greenhouse_shelly_fan_east_2 -> switch.greenhouse_shelly_fan_east`.

If the assertion trips, nothing was written — restore is unnecessary, just diagnose.

**Note:** this bind-mounts the host config directory (the same path Step 2 rsyncs into) rather than relying on `docker exec`, which is unavailable while the container is stopped. Confirm the path resolves first:

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  'ls -la /opt/greenhouse/config/homeassistant/.storage/core.entity_registry'
```

If that path does not exist, find the real one with `docker inspect greenhouse_homeassistant --format '{{json .Mounts}}'` and substitute it.

- [ ] **Step 6: Start HA**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse \
  'docker compose -f /opt/greenhouse/docker-compose.yml start homeassistant && echo STARTED'
```

Wait ~60 s for startup before verifying.

- [ ] **Step 7: Verify the entities exist and are bound correctly**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
docker exec greenhouse_homeassistant python -c "
import json
dev=json.load(open(\"/config/.storage/core.device_registry\"))
ent=json.load(open(\"/config/.storage/core.entity_registry\"))
n={d[\"id\"]:(d.get(\"name_by_user\") or d.get(\"name\")) for d in dev[\"data\"][\"devices\"]}
for e in ent[\"data\"][\"entities\"]:
    if e[\"entity_id\"].startswith((\"switch.greenhouse_shelly\",\"sensor.greenhouse_shelly\")):
        if e.get(\"disabled_by\") is None:
            print(\"%-52s %s\" % (e[\"entity_id\"], n.get(e.get(\"device_id\"))))
" | sort'
```

**This is the acceptance gate for the whole migration.** Every row must pair a `fan_east` entity with device `Shelly - Fan East` and a `fan_west` entity with `Shelly - Fan West`. If any row crosses over, the inversion was not fixed — restore the backup from Step 4 and stop.

Also confirm the three switches are live (not `unavailable`):

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
PW=$(docker exec greenhouse_mariadb printenv MYSQL_ROOT_PASSWORD 2>/dev/null); [ -z "$PW" ] && PW=$(docker exec greenhouse_mariadb printenv MARIADB_ROOT_PASSWORD)
Q="SELECT m.entity_id, s.state FROM states s JOIN states_meta m ON s.metadata_id=m.metadata_id WHERE m.entity_id LIKE \"switch.greenhouse_shelly%\" AND s.last_updated_ts=(SELECT MAX(s2.last_updated_ts) FROM states s2 WHERE s2.metadata_id=s.metadata_id);"
docker exec -e P="$PW" -e Q="$Q" greenhouse_mariadb sh -c '"'"'mysql -uroot -p"$P" homeassistant -N -e "$Q"'"'"''
```

Expected: three rows reading `on` or `off` — **not** `unavailable`.

- [ ] **Step 8: Confirm the physical east/west mapping survived the rename**

Pulse the east fan via its local API and confirm the entity HA now calls "east" is the one that moves:

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
curl -s -m 4 "http://192.168.10.187/rpc/Switch.Set?id=0&on=true"; sleep 8
echo; echo "EAST (.187) draw:"; curl -s -m 4 "http://192.168.10.187/rpc/Switch.GetStatus?id=0" | tr "," "\n" | grep apower
curl -s -m 4 "http://192.168.10.187/rpc/Switch.Set?id=0&on=false"'
```

Then in HA, confirm `switch.greenhouse_shelly_fan_east` was the entity that changed state (Developer Tools → States, or the logbook). Expected draw ~113 W.

- [ ] **Step 9: Verify the no-flow alert stays silent on a healthy pulse**

```bash
ssh -i "$HOME/.ssh/{bitbucket_mb_air_15}" -o IdentitiesOnly=yes greenhouse '
docker exec greenhouse_homeassistant python -m homeassistant --script check_config -c /config >/dev/null 2>&1
curl -s -m 4 "http://192.168.10.194/rpc/Switch.Set?id=0&on=true"; sleep 150
echo "pump draw:"; curl -s -m 4 "http://192.168.10.194/rpc/Switch.GetStatus?id=0" | tr "," "\n" | grep apower
curl -s -m 4 "http://192.168.10.194/rpc/Switch.Set?id=0&on=false"'
```

The pulse runs past the automation's 2-minute settle window. Expected: draw ~108 W, and **no** "ingen strømtrekk" notification. Then check the automation trace (Settings → Automations → *GH Watering no-flow alert* → Traces) — it should show the trigger fired and the power condition correctly blocked the action.

- [ ] **Step 10: Confirm the dashboard renders clean**

Open the dashboard and check the Overview, Automation and System Health views for "Entitet ikke funnet" rows. Expected: none. The Plug Health card should show signal, temperature and voltage for all three plugs.

- [ ] **Step 11: Commit the plan checkboxes and report**

```bash
git add docs/superpowers/plans/2026-07-19-shelly-plug-migration.md
git commit -m "docs(plan): mark Shelly plug migration deployed and verified

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-deploy user actions (not automated)

1. **Delete the three old Tapo devices** from the TP-Link integration in the HA UI. The 2026-07-09 swap left orphaned `1_*` entities lingering in the registry because the dead device was never removed.
2. **Calibrate `gh_pump_min_watts`** after watching a few real pulses. 30 W is a safe default against a measured 108 W draw, but if the pump's steady draw varies with head pressure, raise the floor to roughly half the observed minimum.
3. **Consider the rail-health guard** on the tensiometer nodes (ADS1115 A2/A3 free on both). Unrelated to this migration, but it remains the sharpest open edge: a sagging 5 V rail is indistinguishable from drying soil and could drive phantom watering once the closed loop is enabled.

## Rollback

- **Config:** `git revert` the Task 1-4 commits, rsync the four files, restart HA.
- **Registry:** restore `/config/.storage/core.entity_registry.bak-shelly-20260719` over `core.entity_registry` with HA stopped, then start HA.
- **Blast radius:** watering and fan control. If rollback is needed mid-flight and the cause is unclear, the safest interim state is `input_boolean.gh_automation_enabled` → off (stops fan + alert automations) while leaving watering schedules intact.