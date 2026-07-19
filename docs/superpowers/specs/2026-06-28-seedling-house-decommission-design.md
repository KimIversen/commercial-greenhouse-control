# Seedling House Decommission & Greenhouse Plug Cleanup — Design

**Date:** 2026-06-28
**Status:** Awaiting review

## Context

Three Tapo P100 smart plugs (physically marked **#1, #3, #5**) and a XIAO ESP32-C3
climate sensor were moved from a "Seedling Room 2" setup into the greenhouse and
repurposed. Home Assistant still carries the entire old **Seedling House** subsystem,
which no longer matches reality:

- Plugs were *Oven (#1)* and *Lights (#2)*; they are now **#1 = Vanning (watering)**,
  **#3 = Vifte endevegg øst**, **#5 = Vifte endevegg vest**. Plug **#2** is unplugged.
- `automations.yaml` still runs a seedling **oven thermostat** on `switch.1` and an
  **18h grow-light schedule** on `switch.2`.
- The climate sensor still identifies as `seedling-room2-climate` and is configured
  with static IP **192.168.10.160**, which collides with the Deco X50 Outdoor — so it
  is not reachable at that address.
- `ui-lovelace.yaml` has a full **"Seedling House"** dashboard tab (Room 1 + Room 2).
- `mqtt.yaml` defines MQTT sensors for **Seedling Room 1** and **Seedling Room 2**.

**Decision (user):** the Seedling House is fully decommissioned. Remove all of it from
HA; the Room 2 climate sensor is rebadged as a greenhouse climate sensor.

## Goals

1. Rename the three in-use plugs with consistent labels + entity IDs, keeping the
   marked number 1/3/5.
2. Retire the two seedling automations.
3. Remove the disabled #2 plug and the stale duplicate diagnostic entities.
4. Remove the Seedling House dashboard tab and all seedling MQTT sensors.
5. Rebadge the climate sensor as `greenhouse-climate-2` and fix its IP conflict.

## Non-goals

- Designing new greenhouse automations or a new greenhouse dashboard view (separate
  follow-up). After this change the plugs and climate sensor will have **no dashboard
  card** until that view is built.
- Touching the Archer A5 router, the Deco, or any soil/fertigation/fan/valve configs.

## Detailed changes

### 1. Plug renames (Home Assistant registry, via HA API)

| Marked | New friendly name | Entity ID: from → to |
|---|---|---|
| #1 | `#1 – Vanning` | `switch.1` → `switch.plugg_1_vanning` |
| #3 | `#3 – Vifte endevegg øst` | `switch.greenhouse_3_vifte_endevegg` → `switch.plugg_3_vifte_endevegg_ost` |
| #5 | `#5 – Vifte endevegg vest` | `switch.greenhouse_5_vifte_endevegg` → `switch.plugg_5_vifte_endevegg_vest` |

Area stays `greenhouse`. Only the primary `switch.*` entity ID is standardized;
child entities (LED, auto-off) follow their device.

### 2. Retire seedling automations (`automations.yaml`)

Delete `seedling_room2_stage1_temperature`, `seedling_room2_stage1_lights`, and the
preceding "Seedling Room 2 — Stage 1" comment block.

### 3. Remove leftovers (HA API)

- Delete the disabled **#2** Tapo plug: device + its integration (config) entry.
- Delete stale duplicate diagnostic entities from the earlier setup
  (`sensor.3_signalstyrke`, `sensor.3_ssid`, `sensor.3_on_since`, `sensor.3_device_time`,
  `button.3_omstart`, and the #5 equivalents, plus any `*.2_*` entities orphaned by
  the #2 deletion).

### 4. Remove Seedling House dashboard + MQTT sensors

- `ui-lovelace.yaml`: remove the entire **Seedling House** view (Room 1 + Room 2 cards,
  including the "Room 2 Controls" `switch.1`/`switch.2` card).
- `mqtt.yaml`: remove the Seedling Room 1 and Room 2 MQTT sensor definitions
  (`greenhouse/seedling/room1/*`, `greenhouse/seedling/room2/*`) and the
  "Seedling House" section.

### 5. Rebadge climate sensor (`esphome/seedling-room2-climate.yaml`)

- `device_name`: `seedling-room2-climate` → `greenhouse-climate-2`
- `friendly_name`: `Seedling Room 2 Climate` → `Greenhouse Climate 2`
- `mqtt_topic`: `greenhouse/seedling/room2` → `greenhouse/climate2`
- `device_ip`: `192.168.10.160` → **`192.168.10.151`** (verified free; adjacent to
  `climate-sensor-1` at `.150`)
- Rename the file to `esphome/greenhouse-climate-2.yaml`.
- Entities will arrive via the ESPHome **native API** (`sensor.greenhouse_climate_2_*`);
  no replacement MQTT sensors are added (native API already surfaces temp/humidity).
- **Reflash required.** The ESP is not answering at `.160`, so the first execution
  step is to locate its current address/config. OTA if reachable; otherwise a physical
  USB/serial flash (user action — only the user can do this).

## Execution method

Home-Assistant-side changes (renames, deletions) are applied through the **HA REST/
WebSocket API** using a **long-lived access token** the user creates in their HA profile
(Settings → user profile → Long-lived access tokens). No HA restart, no `.storage`
editing. YAML files (`automations.yaml`, `ui-lovelace.yaml`, `mqtt.yaml`, the ESPHome
config) are edited directly in the repo and deployed via the existing `make deploy-ha`
flow / rsync, then HA config is reloaded.

Token handling: the token is a credential. It will be provided out-of-band (e.g. an env
var set via the `!` prefix or a gitignored file), not pasted into the repo or committed.

## Risks & rollback

- **Entity-ID renames breaking references:** mitigated — the only references to the old
  plug entity IDs are in the seedling automations (being deleted) and the Seedling House
  dashboard card (being deleted). A pre-change `grep` confirms no other references.
- **Climate reflash bricking / IP still wrong:** keep the current YAML until the new
  flash is confirmed online at `.151`; ESPHome keeps the prior firmware on a failed OTA.
- **Dashboard/MQTT deletions:** all YAML edits are in git; revert via `git checkout`.
  HA config validated with **Check Configuration** before reload.
- **HA API changes:** device/entity registry changes are reversible in the UI; note the
  old values before changing.

## Verification

- All three plugs show new labels + entity IDs; `switch.turn_on/off` works on each.
- `#2` plug and stale entities gone from the device/entity list.
- Seedling House tab absent; no `seedling`-prefixed entities remain (Developer Tools →
  States filter `seedling`).
- HA **Check Configuration** passes; no "unknown entity" warnings in the log.
- `greenhouse-climate-2` online at `.151`, reporting temp + humidity via native API.
- `git grep -i seedling configs/` returns nothing.

## Open items

- Exact current address/config of the climate ESP (decides OTA vs serial flash).
- Confirm `.151` should be reserved on the Zyxel (recommended, optional).
