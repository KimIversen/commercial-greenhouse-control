# Shelly 1PM Gen3 Plug Migration — Design

**Date:** 2026-07-19
**Status:** Approved
**Supersedes:** the Tapo/TP-Link plug references established in `2026-06-28-greenhouse-automation-design.md`

## Problem

The three TP-Link/Tapo smart plugs driving watering and the two endwall fans have been
physically replaced with **Shelly 1PM Gen3** devices. The new devices are adopted in Home
Assistant but referenced nowhere — every automation, dashboard card and metric still points at
the old entities, all three of which now read `unavailable`.

Until the references are swapped, watering and fan control are driving dead entities.

## Findings from discovery

### Device inventory

| Device (name_by_user) | IP | Model | Verified draw |
|---|---|---|---|
| Shelly - Watering | 192.168.10.194 | Shelly 1PM Gen3 | 174.6 W inrush → 108.4 W steady |
| Shelly - Fan East | 192.168.10.187 | Shelly 1PM Gen3 | 113.7 W steady |
| Shelly - Fan West | 192.168.10.164 | Shelly 1PM Gen3 | 125.1 W steady |

### The entity-ID inversion (critical)

The two fan entity IDs are **inverted relative to their device names**:

- `switch.greenhouse_shelly_fan_east` → device **Shelly - Fan West** (.164)
- `switch.greenhouse_shelly_fan_east_2` → device **Shelly - Fan East** (.187)

Device .164 was added to HA while still named "Fan East", claiming that slug; it was later
renamed at the device level, and HA does not regenerate entity IDs on rename. The `_2` suffix
on .187 is the collision artifact.

This is not cosmetic. Most fan actions target both plugs together, but `automations.yaml:51`
and `:78` read the **east** plug alone as the representative "are the fans on?" state. A naive
`fan_east` → east mapping binds that logic to the wrong fan.

**Resolved:** user confirmed .164 drives the **west** fan — the device names are authoritative
and the entity IDs are the stale artifact.

### Load verification

Before this migration, both .187 and .194 had `aenergy.total` of exactly 0.000 Wh — no load had
ever drawn through them, so there was no evidence they were wired to pump and fan at all.
Verified by manual pulse on 2026-07-19 (table above); all three confirmed driving real loads.
The old Tapo plugs read `unavailable` and are not in series, so the readings are not confounded.

## Design

### Part A — Entity registry cleanup (server-side, first)

Renames must precede the config references, and are **order-dependent**: `fan_east_2` →
`fan_east` collides unless the current `fan_east` (the west unit) is renamed away first.

1. Back up `.storage/core.entity_registry`
2. Stop HA — it rewrites the registry from memory on exit, so it must be down for an offline edit
3. Rename .164's 10 entities `..._fan_east*` → `..._fan_west*`
4. Rename .187's 10 entities `..._fan_east*_2` → `..._fan_east*`
5. Enable the 9 disabled diagnostics (`signalstyrke`, `temperatur`, `spenning` × 3 devices) and
   give them readable slugs in place of `sensor.shelly1pmg3_<mac>_*`
6. Start HA

Rejected alternative: the websocket API with a long-lived token avoids downtime, but a restart is
required regardless for the `history_stats` entity change, and the existing token is pending
rotation.

### Part B — Entity mapping

| Old | New |
|---|---|
| `switch.greenhouse_6_vanning` | `switch.greenhouse_shelly_watering` |
| `switch.plugg_3_vifte_endevegg_ost` | `switch.greenhouse_shelly_fan_east` |
| `switch.plugg_5_vifte_endevegg_vest` | `switch.greenhouse_shelly_fan_west` |

### Part C — Config changes

**`configs/homeassistant/automations.yaml`** — 6 fan references, 14 watering references.
Also corrects a stale string in `gh_water_watchdog`: the trigger was changed 22 → 16 min but the
alert text still reads "was on >22 min".

**`configs/homeassistant/ui-lovelace.yaml`** — Controls card, Master card, closed-loop pump
reference. The Plug Health card is rebuilt: its Tapo-specific `cloud_connection` /
`signal_level` / `overheated` entities have no Shelly equivalent, so it moves to
`signalstyrke` / `temperatur` / `spenning` plus the always-enabled
`overheating` / `overpowering` / `overvoltage` / `overcurrent`. Fan power sensors added.

**`configs/homeassistant/packages/greenhouse_metrics.yaml`** — 2 `history_stats` entity IDs.

**`CLAUDE.md`** — plug documentation is now factually wrong.

### Part D — Power-verified watering watchdog (new)

The Shelly 1PM's power metering closes a failure mode that was previously invisible: a commanded
relay and a dead pump look identical to HA. The 2026-07-06 dead-supply episode is this class of
fault.

New automation `gh_water_no_flow_alert`:

- **Trigger:** `switch.greenhouse_shelly_watering` → `on` for `00:02:00` (settle time)
- **Condition:** `sensor.greenhouse_shelly_watering_effekt` < `input_number.gh_pump_min_watts`
- **Action:** `script.gh_notify`

**Alert-only — it does not force the pump off.** A flaky power reading must not be able to
cancel a legitimate watering pulse; the existing 16-minute watchdog already covers stuck-on.

`input_number.gh_pump_min_watts` defaults to **30 W**, derived from the measured 108 W steady
draw — far below true draw, far above noise.

## Consequences

**History discontinuity.** `GH Water Ontime 24h` / `7d` are keyed to the old entity. After
cutover the 24h figure is wrong for one day and the 7d figure for one week; they rebuild against
the new entity rather than migrating. Analytics only — no operational effect.

**Renamed Shelly history.** Renaming an entity ID does not migrate historical `states` rows.
The affected devices are days old, so the loss is negligible.

**Unchanged.** The tensiometer closed loop stays in shadow mode
(`gh_watering_closedloop_enabled` = off) and the outstanding rail-health guard recommendation is
untouched by this work.

## Out of scope

- Deleting the three old Tapo devices from the TP-Link integration (user UI action; prevents the
  orphaned-entity lingering seen in the 2026-07-09 swap)
- The Kasa integration error-spam against `.161`
- The ADS1115 rail-health guard

## Verification

1. `hass --script check_config` exits 0
2. The three new switch entities exist and are not `unavailable`
3. Fan automation reads `switch.greenhouse_shelly_fan_east` and it maps to the east fan
4. A manual watering pulse registers non-zero `sensor.greenhouse_shelly_watering_effekt`
5. `gh_water_no_flow_alert` does not fire during a healthy pulse
6. Plug Health card renders with no "Entitet ikke funnet" rows

Per the 2026-07-19 deploy gotcha: run a full-directory `rsync -n --itemize-changes` before
deploying any single file, to catch other undeployed divergence.
