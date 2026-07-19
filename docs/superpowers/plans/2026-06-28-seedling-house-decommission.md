# Seedling House Decommission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is an ops/config plan: each task's "test" is a verification command with expected output, not a unit test.

**Goal:** Remove the obsolete Seedling House subsystem from Home Assistant and rebadge its surviving hardware (3 Tapo plugs + 1 climate ESP) for the greenhouse.

**Architecture:** YAML config files (`automations.yaml`, `ui-lovelace.yaml`, `mqtt.yaml`) are edited in the repo and deployed by rsync to `greenhouse:/opt/greenhouse/config/homeassistant/`, applied with one HA restart. In-HA registry changes (plug rename, deletions) are driven through the HA WebSocket API via a long-lived token, run from inside the `greenhouse_homeassistant` container. The climate ESP is rebadged in its ESPHome YAML and reflashed.

**Tech Stack:** Home Assistant (Docker, host networking), HA WebSocket API, ESPHome, MariaDB/MQTT untouched.

## Global Constraints

- Target host: SSH alias `greenhouse` (192.168.10.107); HA dir `/opt/greenhouse/config/homeassistant`; compose dir `/opt/greenhouse`.
- Do NOT deploy with `make deploy-ha` (rsyncs the whole dir incl. unrelated WIP). Deploy only the specific edited files by name.
- Never echo, commit, or write the HA token to the repo. It is provided as `$HA_TOKEN` in the session via the `!` prefix.
- New plug entity IDs (verbatim): `switch.plugg_1_vanning`, `switch.plugg_3_vifte_endevegg_ost`, `switch.plugg_5_vifte_endevegg_vest`.
- New plug labels (verbatim): `#1 – Vanning`, `#3 – Vifte endevegg øst`, `#5 – Vifte endevegg vest`.
- Climate ESP new identity: device `greenhouse-climate-2`, friendly `Greenhouse Climate 2`, MQTT topic `greenhouse/climate2`, static IP `192.168.10.151`.
- All changes stay in the git working tree; do NOT commit unless the user asks (we are on `main` → branch first if so).

---

## Prerequisites (resolve before Tasks 4–6)

- [ ] **P1 — HA token.** Ask the user to create a long-lived access token (HA → profile → Long-lived access tokens) and provide it to the session with: `! export HA_TOKEN='<token>'`. Verify reachable: `ssh greenhouse "docker exec -e HA_TOKEN greenhouse_homeassistant ..."` is NOT how env crosses; instead pass the token value through stdin to the in-container script (see Task 4). Confirm presence locally without printing it: `[ -n "$HA_TOKEN" ] && echo "token set" || echo "MISSING"`.
- [ ] **P2 — Locate the climate ESP.** Needed only for Task 6. Run the discovery in Task 6 Step 1; if offline, Task 6 becomes a user serial-flash checkpoint. Tasks 1–5 do not depend on this.

---

## Task 1: Retire the two seedling automations

**Files:**
- Modify: `configs/homeassistant/automations.yaml` (remove the "Seedling Room 2 — Stage 1" comment block + `seedling_room2_stage1_temperature` + `seedling_room2_stage1_lights`)

- [ ] **Step 1: Re-read the block to get exact boundaries**

Run: `sed -n '27,97p' configs/homeassistant/automations.yaml`
Expected: the comment block (line ~27) through the end of `seedling_room2_stage1_lights` (line ~96).

- [ ] **Step 2: Delete the comment block + both automations** using Edit (old_string = the full block from `# ===...Seedling Room 2...` through the last line of the lights automation; new_string = empty or a single blank line). Confirm no other automation is adjacent-merged.

- [ ] **Step 3: Verify no seedling automations remain in the file**

Run: `grep -nc seedling configs/homeassistant/automations.yaml`
Expected: `0`

- [ ] **Step 4: Verify YAML still parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('configs/homeassistant/automations.yaml')); print('OK')"`
Expected: `OK`

(Deployment + reload happens once in Task 3 Step 4, after all three YAML files are edited.)

---

## Task 2: Remove the Seedling House dashboard tab

**Files:**
- Modify: `configs/homeassistant/ui-lovelace.yaml` (remove the entire `- title: Seedling House` view)

- [ ] **Step 1: Find the view's start and the next view's start**

Run: `grep -nE '^  - title:|^  - path:' configs/homeassistant/ui-lovelace.yaml | head`
Expected: identifies the `Seedling House` view start (~line 4) and the following view, so we know where to cut.

- [ ] **Step 2: Read the full view to confirm its extent**

Run: `sed -n '1,100p' configs/homeassistant/ui-lovelace.yaml`
Expected: the Seedling House view from its `- title:` line up to (not including) the next `- title:` view.

- [ ] **Step 3: Delete the whole Seedling House view** using Edit (old_string spanning from `  - title: Seedling House` through the last line before the next view's `  - title:`). Keep the `views:` key and following views intact.

- [ ] **Step 4: Verify no seedling refs + YAML parses**

Run: `grep -nc seedling configs/homeassistant/ui-lovelace.yaml`
Expected: `0`
Run: `python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/ui-lovelace.yaml')); print('OK')"`
Expected: `OK`

---

## Task 3: Remove seedling MQTT sensors + deploy + restart

**Files:**
- Modify: `configs/homeassistant/mqtt.yaml` (remove Seedling Room 1 & Room 2 sensor blocks and the "Seedling House" section)

- [ ] **Step 1: Locate the seedling blocks**

Run: `grep -nE 'Seedling|greenhouse/seedling' configs/homeassistant/mqtt.yaml`
Expected: the Room 1 + Room 2 sensor definitions (~lines 6–35) and the section at ~line 101.

- [ ] **Step 2: Read and delete those blocks** using Edit, removing each `- name: "Seedling Room ..."` sensor entry and the "SEEDLING HOUSE" comment headers. Leave all non-seedling MQTT sensors untouched.

- [ ] **Step 3: Verify removal + YAML parses**

Run: `grep -nc -i seedling configs/homeassistant/mqtt.yaml`
Expected: `0`
Run: `python3 -c "import yaml; yaml.safe_load(open('configs/homeassistant/mqtt.yaml')); print('OK')"`
Expected: `OK`

- [ ] **Step 4: Deploy the three edited files + restart HA**

```bash
cd /Users/kimiversen/solstad/commercial-greenhouse-control
rsync -avz configs/homeassistant/automations.yaml configs/homeassistant/ui-lovelace.yaml configs/homeassistant/mqtt.yaml greenhouse:/opt/greenhouse/config/homeassistant/
ssh greenhouse 'cd /opt/greenhouse && docker compose restart homeassistant'
```
Expected: rsync sends 3 files; HA restarts.

- [ ] **Step 5: Verify HA healthy + seedling entities gone**

```bash
ssh greenhouse 'for i in $(seq 1 25); do c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8123/); [ "$c" = 200 ] && { echo "HA 200"; break; }; sleep 3; done'
```
Expected: `HA 200`. Then in HA → Developer Tools → States, filter `seedling` → no Room 1/Room 2 MQTT/dashboard entities remain (the ESP-native `sensor.seedling_room_2_climate_*` may still show until Task 6).

---

## Task 4: Rename the three plugs (HA WebSocket API)

**Files:**
- Create (scratch, not committed): `/private/tmp/claude-501/.../scratchpad/ha_ws.py`

**Interfaces:**
- Consumes: `$HA_TOKEN` (P1), piped to the script via stdin alongside commands.
- Produces: renamed entity IDs used by verification + future greenhouse work.

- [ ] **Step 1: Write a reusable WS helper** that reads the token from its first stdin line and a JSON list of commands from the rest, authenticates to `ws://localhost:8123/api/websocket`, sends each command, prints `id`+`success`. Use the container's `aiohttp`.

```python
import asyncio, json, sys, aiohttp
async def main():
    data = sys.stdin.read().splitlines()
    token = data[0].strip()
    cmds = json.loads("\n".join(data[1:]))
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect("ws://localhost:8123/api/websocket") as ws:
            await ws.receive_json()  # auth_required
            await ws.send_json({"type": "auth", "access_token": token})
            if (await ws.receive_json()).get("type") != "auth_ok":
                print("AUTH FAILED"); return
            i = 0
            for c in cmds:
                i += 1; c["id"] = i
                await ws.send_json(c)
                while True:
                    m = await ws.receive_json()
                    if m.get("id") == i and m.get("type") == "result":
                        print(c.get("type"), c.get("entity_id") or c.get("device_id") or c.get("entry_id"), "->", m.get("success"), (m.get("error") or ""))
                        break
asyncio.run(main())
```

- [ ] **Step 2: Dump current plug entity/device IDs** (so we target the right ones). Pipe token + a `config/entity_registry/list` + `config/device_registry/list` request and grep for the plug rows. Confirm the three live switch entity IDs (`switch.1`, `switch.greenhouse_3_vifte_endevegg`, `switch.greenhouse_5_vifte_endevegg`) and their device IDs.

- [ ] **Step 3: Send the three entity renames + three device-name updates.** Commands array:

```json
[
 {"type":"config/entity_registry/update","entity_id":"switch.1","new_entity_id":"switch.plugg_1_vanning"},
 {"type":"config/entity_registry/update","entity_id":"switch.greenhouse_3_vifte_endevegg","new_entity_id":"switch.plugg_3_vifte_endevegg_ost"},
 {"type":"config/entity_registry/update","entity_id":"switch.greenhouse_5_vifte_endevegg","new_entity_id":"switch.plugg_5_vifte_endevegg_vest"},
 {"type":"config/device_registry/update","device_id":"<#1-id>","name_by_user":"#1 – Vanning"},
 {"type":"config/device_registry/update","device_id":"<#3-id>","name_by_user":"#3 – Vifte endevegg øst"},
 {"type":"config/device_registry/update","device_id":"<#5-id>","name_by_user":"#5 – Vifte endevegg vest"}
]
```

Run by piping `printf '%s\n%s' "$HA_TOKEN" "$CMDS" | ssh greenhouse "docker exec -i greenhouse_homeassistant python3 - " < ha_ws.py` (token never printed).

- [ ] **Step 4: Verify the renames took**

Query `config/entity_registry/list` again; expect the three new IDs present and the old IDs absent. Also confirm each device's `name_by_user` updated.
Expected: all six commands returned `success: true`; new entity IDs exist.

---

## Task 5: Delete the #2 plug + stale duplicate entities (HA WebSocket API)

**Files:** reuses `ha_ws.py`.

- [ ] **Step 1: Get the #2 plug's config entry ID + the stale entity IDs.** From the registry dump, find the disabled `#2` device's `config_entry_id` and list the leftover `*.3_*` / `*.5_*` / `*.2_*` diagnostic entities (e.g. `sensor.3_signalstyrke`, `sensor.3_ssid`, `sensor.3_on_since`, `sensor.3_device_time`, `button.3_omstart`, and #5 equivalents).

- [ ] **Step 2: Delete the #2 config entry** (removes its device + entities):

```json
[{"type":"config_entries/delete","entry_id":"<#2-config-entry-id>"}]
```

- [ ] **Step 3: Remove the stale duplicate entities** (one command each):

```json
[{"type":"config/entity_registry/remove","entity_id":"sensor.3_signalstyrke"}, ...one per stale entity... ]
```

- [ ] **Step 4: Verify**

Query the registry; expect the `#2` device gone and the stale entities absent.
Expected: deletions returned `success: true`; Developer Tools → States filter `.2`/`signalstyrke` shows nothing.

---

## Task 6: Rebadge + reflash the climate ESP

**Files:**
- Rename + modify: `esphome/seedling-room2-climate.yaml` → `esphome/greenhouse-climate-2.yaml`

- [ ] **Step 1: Locate the device's current state.**

```bash
ssh greenhouse 'for p in 6053 3232; do for ip in 160 151 156 157 158 159; do (echo >/dev/tcp/192.168.10.$ip/$p) >/dev/null 2>&1 && echo "192.168.10.$ip:$p OPEN"; done; done'
```
Also check the ESPHome dashboard (`http://greenhouse:6052`) for the device's online status.
Expected: identifies a reachable ESPHome port, or confirms the device is offline → go to Step 5 (serial flash, user action).

- [ ] **Step 2: Edit the YAML** — set `device_name: greenhouse-climate-2`, `friendly_name: "Greenhouse Climate 2"`, `mqtt_topic: "greenhouse/climate2"`, `device_ip: "192.168.10.151"`. Then `git mv esphome/seedling-room2-climate.yaml esphome/greenhouse-climate-2.yaml` (or `mv` since untracked).

- [ ] **Step 3: Deploy the ESPHome config**

```bash
rsync -avz esphome/greenhouse-climate-2.yaml greenhouse:/opt/greenhouse/config/esphome/
ssh greenhouse 'rm -f /opt/greenhouse/config/esphome/seedling-room2-climate.yaml'
```

- [ ] **Step 4 (if OTA reachable): Compile + OTA flash** via the ESPHome dashboard/CLI for `greenhouse-climate-2.yaml`. Then verify it comes up at `.151`: `ssh greenhouse 'ping -c2 192.168.10.151'` and check MQTT `greenhouse/climate2/temperature`.

- [ ] **Step 5 (if offline / not OTA-able): USER CHECKPOINT.** Ask the user to USB-connect the XIAO ESP32-C3 and flash `greenhouse-climate-2.yaml` (esphome run). This is a physical action only the user can do. Pause here.

- [ ] **Step 6: Clean up old climate entities + verify new ones.** After the device is online as `greenhouse-climate-2`, in HA the ESPHome integration creates `sensor.greenhouse_climate_2_temperature` / `_humidity`. Remove the now-unavailable old `seedling_room_2_climate_*` device/entities via the HA UI or `config_entries`/registry (reuse `ha_ws.py`).
Expected: `sensor.greenhouse_climate_2_temperature` reports a live value; no `seedling`-prefixed entities remain.

---

## Task 7: Final verification

- [ ] **Step 1: No seedling references anywhere in HA config**

Run: `cd /Users/kimiversen/solstad/commercial-greenhouse-control && git grep -in seedling -- configs/ esphome/ ; echo "exit=$?"`
Expected: no matches (grep exit 1).

- [ ] **Step 2: HA config check passes**

Run: `ssh greenhouse 'docker exec greenhouse_homeassistant python3 -m homeassistant --script check_config -c /config' 2>&1 | tail -5`
Expected: no errors.

- [ ] **Step 3: Functional check** — toggle each renamed plug:

Use `ha_ws.py` or REST `POST /api/services/switch/toggle` for `switch.plugg_1_vanning`, `switch.plugg_3_vifte_endevegg_ost`, `switch.plugg_5_vifte_endevegg_vest`; confirm each physically actuates.
Expected: all three respond.

- [ ] **Step 4: Summarize + offer commit.** Report what changed. We are on `main`; if the user wants it committed, create a branch first, then commit the YAML edits, the renamed ESPHome file, and the spec/plan docs.

---

## Self-Review (author checklist)

- **Spec coverage:** Goals 1–5 → Tasks 4/5 (plugs+cleanup), 1 (automations), 4/5 (leftovers), 2/3 (dashboard+MQTT), 6 (climate). ✓
- **Placeholders:** `<#N-id>` / `<#2-config-entry-id>` are runtime-resolved IDs with an explicit fetch step (Task 4 Step 2, Task 5 Step 1), not unspecified work. ✓
- **Ordering:** references removed (Tasks 1–3) before entity renames/deletes (Tasks 4–5) to avoid broken refs. ✓
- **Reversibility:** YAML in git; registry changes reversible in UI; ESP keeps prior firmware on failed OTA. ✓
