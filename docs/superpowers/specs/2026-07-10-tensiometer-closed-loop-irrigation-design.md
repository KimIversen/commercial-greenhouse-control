# Tensiometer-driven closed-loop irrigation (schedule as backup)

**Date:** 2026-07-10
**Status:** Design approved — pending spec review, then implementation plan
**Supersedes:** the parked `docs/superpowers/specs/2026-07-01-tensiometer-irrigation-design.md` (Phase 2)
**Deploy constraint:** cannot deploy until back on the greenhouse LAN (user currently remote/Nabu Casa only).

## Problem

The time-based watering schedule (07:00 10 min / 10:00 8 min / 12:00 7 min ≈ 25 min/day
on `switch.greenhouse_6_vanning`) is **too lean for this substrate and heat**, and it
can't adapt to the weather. Evidence from 2026-07-10 (first clean day, plug + sensors both working):

- The 07:00 pulse **fired** (confirmed via switch history) but tension kept climbing —
  10 min can't out-run the morning dry-down, and short pulses on already-dry peat wet
  **inefficiently** (channeling), delivering <½ of a longer pulse's effect.
- Overnight the pots did **not** reset; by ~09:00 avg tension had ratcheted to ~32 kPa
  (ch1 ~40, ch2 ~25) — the driest point of the window.
- A **manual 20-min pulse** then dropped avg 32 → 11.5 kPa (ch2 → 6.6, ch1 → 16.4),
  proving delivery is fine and that **~20 min ≈ a full refill**.

So the problem is under-dosing by an open-loop schedule, not plumbing. We want irrigation
driven by actual substrate water tension, keeping a **balanced / mild-generative** band
(the deficit-for-Brix sweet spot), with the schedule retained only as a safety fallback.

## Calibration basis (measured 2026-07-09/10)

| Quantity | Value | Source |
|---|---|---|
| Full refill dose | ~20 min → avg 32→~11 kPa | manual test pulse |
| Controlled top-up dose | ~13 min (chosen; avoids over-wetting ch2) | interpolated |
| Peak daytime dry rate | ~3 kPa/h | afternoon dry-back curves |
| Tolerated band | ~10 kPa (fresh) … ~35 kPa (no visible stress) | 2 days of curves |
| Probe divergence | ch1 runs ~7–15 kPa **drier** than ch2 | both curves |
| Sensor→pulse lag | tension keeps moving ~20–30 min after pump off | manual pulse tail |

## Goals / Non-goals

**Goals:** substrate-tension-driven pulses maintaining a balanced band; schedule as a
sensor-failure fallback; every setpoint tunable from the dashboard; strong safety guards;
gentle pre-dark dry-back (anti-crack).

**Non-goals (future):** per-zone control (Sun Gold vs Black Cherry via the valve
controller's 5 zones); weather/forecast feed-forward; automatic setpoint learning.

## Approach

**Closed loop is primary; the 07/10/12 schedule is backup.** When tension is healthy the
loop controls all watering; the scheduled pulses fire **only** when tension is
unavailable/stale or the loop is disabled. (Rejected alternative: schedule-as-base with
tensiometer only adding/skipping pulses — more conservative but two interacting systems;
kept as a fallback option if the loop proves fiddly.)

### Setpoints (balanced band; all tunable helpers)

| Helper | Default | Meaning |
|---|---|---|
| `input_number.gh_tension_on` | 30 | pulse when avg kPa ≥ this |
| `input_number.gh_tension_ch1_cap` | 40 | …or when the drier probe (ch1) ≥ this (safety) |
| `input_number.gh_tension_off` | 12 | skip pulsing if avg already ≤ this (wet) |
| `input_number.gh_pulse_minutes` | 13 | pump on-time per pulse |
| `input_number.gh_pulse_wait_minutes` | 30 | min gap between pulses (covers sensor lag) |
| `input_number.gh_water_daily_cap_minutes` | 90 | max total pump minutes per day |
| `input_datetime.gh_water_window_start` | 06:00 | earliest pulse |
| `input_datetime.gh_water_window_end` | 18:00 | latest pulse (≈3 h before sunset) |

### Control logic — automation `gh_water_tension_loop`

Trigger: `time_pattern` every 5 min (plus a `numeric_state` trigger on avg crossing
`gh_tension_on` for responsiveness). Fire one `gh_pulse_minutes` pulse **iff ALL**:

1. `input_boolean.gh_automation_enabled` on **and** `gh_watering_ha_enabled` on **and**
   new `input_boolean.gh_watering_closedloop_enabled` on;
2. tension **valid** — `sensor.greenhouse_tensiometer_average_kpa` is a number (not
   `unavailable`/`unknown`). This one test covers **both** a disconnected device (native-API
   entities all go `unavailable`) **and** a faulted sensor (the firmware guard publishes
   `NaN`→`unavailable` at ~0 V). Optional extra hung-device staleness check must use
   `last_reported` (**not** `last_updated`, which only changes when the *value* changes) < 5 min;
3. `avg ≥ gh_tension_on` **or** `ch1 ≥ gh_tension_ch1_cap`;
4. `avg > gh_tension_off`;
5. ≥ `gh_pulse_wait_minutes` since `input_datetime.gh_last_pulse`;
6. current time within `[gh_water_window_start, gh_water_window_end]`;
7. `input_number.gh_water_today_minutes` + `gh_pulse_minutes` ≤ `gh_water_daily_cap_minutes`.

Action: turn on `switch.greenhouse_6_vanning`; wait `gh_pulse_minutes`; turn off. The
**dose-then-wait** discipline (guard 5) prevents chasing the lagged reading and overshooting.

Probe strategy: trigger on **avg** for normal control, with the **ch1 (drier) cap** as the
safety trigger so the fastest-drying pot never runs away.

### Backup schedule

Modify `gh_water_0700` / `gh_water_1000` / `gh_water_1200`: add a condition so each fires
**only if** `gh_watering_closedloop_enabled` is off **or** tension is unavailable
(guard 2's validity test, negated: avg is `unavailable`/`unknown`). Healthy sensors ⇒
scheduled pulses stay dormant.

### Safety guards

- **Sensor-dead → schedule fallback.** Enabled by the 2026-07-09 firmware fault-guard: a
  dead/unpowered TX-E now reports `unavailable` (not a false 100 kPa), so guard 2 fails,
  the loop stands down, and the backup schedule waters instead. Without that guard a battery
  death would read "bone dry" and the loop would water non-stop — this dependency is why the
  guard shipped first.
- **Daily cap** (guard 7) bounds any runaway.
- **Min interval** (guard 5) prevents rapid re-fire before tension responds.
- **Pump watchdog** — tighten existing `gh_water_watchdog` from 22 → **16 min** force-off
  (max intended dose is 13).
- **Two master switches** — existing `gh_watering_ha_enabled` plus new
  `gh_watering_closedloop_enabled`, so the operator can drop to pure schedule instantly.
- **Window** — no overnight watering; last pulse ~3 h before sunset for the anti-crack dry-back.

## New / changed Home Assistant entities

**New helpers** (follow existing `sensors/automation_*.yaml` include pattern):
`input_boolean.gh_watering_closedloop_enabled`; `input_number` × gh_tension_on/off,
gh_tension_ch1_cap, gh_pulse_minutes, gh_pulse_wait_minutes, gh_water_daily_cap_minutes,
gh_water_today_minutes (accumulator); `input_datetime` × gh_water_window_start,
gh_water_window_end, gh_last_pulse.

**New automations:** `gh_water_tension_loop` (controller);
`gh_water_daily_reset` (zero `gh_water_today_minutes` at 00:00).

**Modified automations:** `gh_water_0700/1000/1200` (backup condition);
`gh_water_watchdog` (16 min); `gh_watering_tracker` (also stamp `gh_last_pulse` on pump-on
and add the finished duration to `gh_water_today_minutes` on pump-off).

**Reused:** `switch.greenhouse_6_vanning`; `sensor.greenhouse_tensiometer_{average,1,2}_kpa`.

## Failure modes

| Failure | Behavior |
|---|---|
| One probe dies | average uses the survivor (firmware already NaN-safe); loop keeps running |
| Both probes die / stale | avg unavailable → guard 2 fails → **backup schedule** takes over |
| Pump sticks on | `gh_water_watchdog` force-off at 16 min |
| Setpoints mis-set too dry | daily cap + operator toggle bound the damage |
| HA restart mid-pulse | switch state persists; watchdog catches a stranded pump |

## Deployment & rollback

Deploy on the LAN: `rsync` changed config to the server + Reload Automations / Reload
Helpers (no restart needed for automations + input helpers). **Rollout:** ship with
`gh_watering_closedloop_enabled` **off** first — observe the loop's *decisions* in the
logbook for a day against the live schedule, then flip it on. **Rollback:** turn the toggle
off → instantly back to pure schedule; revert config to remove entities.

## Success criteria

- With the loop on, avg tension stays within ~10–32 kPa on hot days without manual pulses,
  and mornings reset to <12 kPa.
- ch1 never sustained above ~42 kPa.
- Killing sensor power (battery pull test) makes the loop stand down and the schedule water.
- No pump run > 16 min; daily total ≤ cap.

## Open questions

- Confirm actual sunset-relative window vs fixed 18:00 (Norway summer sunset is ~22:45 now,
  drifts fast toward autumn — may want `gh_water_window_end` = sunset − 3 h dynamically).
- After ~1 week, revisit dose (13 min) and the ch1/ch2 divergence (reposition a probe?).
