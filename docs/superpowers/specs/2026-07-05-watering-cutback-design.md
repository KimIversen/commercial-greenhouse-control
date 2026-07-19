# Watering Cutback — Move to HA + Leaner Schedule (Design)

**Status:** Approved 2026-07-05. Ready for implementation plan.
**Author context:** Pots found saturated (~5 kPa on the new tensiometers); user wants them drier.
**Related:** [[docs/superpowers/specs/2026-07-01-tensiometer-irrigation-design.md]] (parked Phase 2),
tensiometer install `docs/superpowers/specs/2026-07-04-tensiometer-esphome-design.md`.

---

## Context

The new TX-E tensiometers (node `.161`, installed 2026-07-04) read **~5 kPa** in-pot — essentially
saturated. Investigating the pump switch `switch.plugg_1_vanning` history (HA recorder, last 4 days)
found **two** watering sources, both **outside** Home Assistant:

1. **A Tapo daytime schedule** — fixed pulses at **05:00 (20m) / 07:00 (15m) / 09:00 (10m) /
   11:00 (10m) / 13:00 (15m) ≈ 70 min/day** (~2.3 L/plant/day at 2 L/h drip, estimate).
2. **Tapo "Away Mode"** — randomized overnight on/off (e.g. 07-04 at 01:30, 02:24, 02:32, and a
   ~17-min run at 03:43). This was the mystery "watering every night a couple times." **User
   disabled Away Mode 2026-07-05.**

The HA watering automations (`gh_water_*` in `configs/homeassistant/automations.yaml`) exist but are
**dormant** behind `input_boolean.gh_watering_ha_enabled` (OFF). Nothing in HA fires at night.

Root cause of "too wet": the Tapo schedule delivers ~70 min/day with no substrate feedback, and
Away Mode added uncontrolled night runs on top.

## Goal

Get the pots drier and put watering under one auditable controller (HA), with a **leaner blind
schedule** whose volume we tune by *watching* the tensiometer dry-back over the coming week.

## Non-goals (for now)

- Tensiometer-**triggered** pulsing (Phase 2) — deferred until ~1–2 weeks of baseline exists; a hard
  kPa threshold isn't trustworthy yet for this peat/pine substrate.
- Per-variety / per-zone steering (single pump today).
- Any kPa control gate or sensor-fail fallback logic (schedule stays purely time-based this phase).

---

## Design

### 1. Cutover (Tapo → HA), one-time

- **User (Tapo app):** disable the daytime schedule on plug #1 (`Vanning`). Away Mode already off.
  After this, Tapo drives nothing.
- **HA:** set `input_boolean.gh_watering_ha_enabled` → **ON** (`gh_automation_enabled` already on).
- **Ordering matters:** disable Tapo *before/at* enabling HA, else both water the same pump
  (double dose).

### 2. New leaner schedule

Replaces the five old pulses. All gated by `gh_automation_enabled` **and**
`gh_watering_ha_enabled` (unchanged pattern), targeting `switch.plugg_1_vanning`.

| Time  | Duration |
|-------|----------|
| 07:00 | 10 min   |
| 10:00 | 8 min    |
| 12:00 | 7 min    |

- **~25 min/day** total (≈0.8 L/plant/day at 2 L/h, estimate — was ~2.3 L). ~65% cut.
- **Morning-weighted, nothing after 12:00** → long afternoon + overnight dry-back ending well before
  the ~22:45 sunset. This is the daily gentle dryback the parked design calls for.
- **Evening nudge dropped** (`gh_water_evening_nudge` removed/disabled) — it adds late water and
  fights the dryback. A small pre-sunset pulse can be re-added later if a heat spell over-dries.

### 3. Keep safety + telemetry (unchanged)

- **`gh_water_watchdog`** — force-off if pump on >22 min. Pure insurance (longest pulse now 10 min).
- **`gh_watering_tracker`** — keeps recording last-watering start/duration into the input helpers.
- **Tensiometer = monitor only.** `sensor.greenhouse_tensiometer_{1,2,average}_kpa` stay purely
  observational this phase; no automation reads them yet.

### 4. Tuning loop (this next week — operational, not code)

- Watch `sensor.greenhouse_tensiometer_average_kpa` for a daily **saw-tooth**: tension rises (dries)
  through afternoon/night, gently re-wet each morning — not a flat line pinned near ~5 kPa.
- **Flat & wet** → cut minutes further (or add a short dry-down). **Climbing too high/fast** (wilt
  risk) → add minutes back. Adjust durations only; keep the shape.
- After ~1–2 weeks of baseline, revisit Phase 2 (tensiometer-triggered pulsing) with real numbers.

### 5. Rollback

Fully reversible, same day: flip `gh_watering_ha_enabled` **OFF** (and/or re-enable the Tapo
schedule), or just bump pulse durations back up.

---

## Implementation notes (for the plan)

- Edit `configs/homeassistant/automations.yaml`:
  - Reduce to **3 pulses** at 07:00/10:00/12:00 with 10/8/7 min (repurpose/rename the existing
    `gh_water_0700/0900/1100`; **remove** `gh_water_1300`, `gh_water_1500`, `gh_water_evening_nudge`).
  - Leave `gh_water_watchdog` and `gh_watering_tracker` intact.
- Set `input_boolean.gh_watering_ha_enabled` ON — decide mechanism (dashboard toggle vs. config
  default) during planning; the *user* still must disable Tapo first.
- Deploy path: `make deploy-ha` (pushes HA config + restart) per the Makefile.
- **Verification:** confirm in the recorder that the pump fires only at 07:00/10:00/12:00 for the
  right durations and never overnight; watch avg kPa begin to rise.

## Open items (non-blocking)

1. **Emitter flow rate + plant/emitter count** — to convert minutes → L/plant precisely (2 L/h is an
   estimate). Confirm to firm up volume figures.
2. **Do the pots drain?** If not free-draining, saturation is accumulation, not just excess ET —
   affects how fast the dryback appears. Observe during the tuning week.
3. Starting cut is ~25 min/day; if that dries too hard, first fallback is ~35 min/day (same 3-pulse
   shape, longer durations).
