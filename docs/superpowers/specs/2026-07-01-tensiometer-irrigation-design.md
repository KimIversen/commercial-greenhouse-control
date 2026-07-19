# Tensiometer-Driven Deficit Irrigation — Design (PARKED, gated on tensiometer install)

**Status:** Parked 2026-07-01. Resume when tensiometers are physically installed and reporting.
**Depends on:** [[research: docs/research/2026-07-01-deficit-irrigation-brix.md]] and the tomato
growth program (`Tomat vekstprogram 2026.pdf`, §2.1 irrigation/tensiometer targets).
**Supersedes intent of:** the "Thursday same-day pre-harvest dryback" idea — see Context.

---

## Context

Current watering (in `configs/homeassistant/automations.yaml`, dormant behind
`input_boolean.gh_watering_ha_enabled`): **5 fixed time pulses** on `switch.plugg_1_vanning`
(2 L/h drip) at 07:00/09:00/11:00/13:00/15:00 + a hot-day evening nudge + a 22-min watchdog. It is
**blind** — no substrate feedback.

We started out intending a Thursday-evening pre-harvest dryback to raise Brix. Deep research
(2026-07-01) showed that is the **wrong lever**:
- A same-day dryback on already-pink fruit does **not** raise Brix (ripe fruit is hydraulically
  disconnected from plant water status).
- Cracking is triggered by **rehydration surges** after dry spells, so a "skip afternoon → re-water"
  cycle would *increase* split risk in Sun Gold, not reduce it.
- What actually builds Brix is a **sustained, moderate deficit across fruit development**, kept steady.
- Cherry types tolerate moderate deficit on BER; the safeguard is protecting *early*-stage fruit.
- Every quantitative setpoint in the literature needs substrate-moisture feedback the system lacks.

The user is **installing tensiometers**, which closes that measurement gap and makes the growth
program's kPa targets directly implementable. This design is the plan to execute once they're live.

## Goal

Replace the fixed time schedule with **tensiometer-feedback irrigation** that:
1. Holds a **steady, mild generative deficit** through the day (the real Brix lever).
2. **Avoids rehydration surges** (gentle morning re-wet) to protect split-prone Sun Gold.
3. **Ends before sunset** for a *gentle, consistent* overnight dryback — every day, not just Thursday.
4. Stays **BER-safe** (moderate, never deep; protect young fruit).
5. **Fails safe** to a conservative time schedule if a sensor drops out.

## Non-goals
- Same-day Thursday dryback for Brix (refuted — see research).
- Deep/aggressive dryback (loses yield, no quality gain).
- Per-truss or per-plant control.

---

## Strategy (evidence-based, to be tuned against real data)

**Trigger-based pulsing.** Fire a short pulse when substrate tension rises to the stage *trigger
kPa*; stop; let tension climb back. Frequent small pulses → steady root zone (anti-BER, anti-crack).

**Program bands (harvest stage, from growth program §2.1) as the starting envelope:**
- Trigger: **3.0–3.5 kPa** · overnight dryback ceiling: **4.0–5.0 kPa** · drain target: **10–20%**
- Volume: **1.5–3.0 L/plant/day** in **6–12 pulses** · **last irrigation 2–3 h before sunset**
- Variety: **Sun Gold wetter** (lower trigger, it splits easily); **Black Cherry drier** (more flavor
  concentration). If both share one valve, steer to the wetter (Sun Gold) setpoint.

**Mild sustained deficit for Brix.** Set the daytime trigger toward the *drier* edge of the band
(generative steering) — but never deep. Moderate wins; deep loses yield.

**Gentle overnight dryback, every day.** Stop irrigating ~2–3 h before sunset; allow tension to rise
toward the ~4–5 kPa ceiling overnight. This is the daily version of what the Thursday dryback was
trying to do, and it's the supported one.

**Anti-crack morning ramp.** After the overnight dryback, re-wet with *small pulses ramping up*, not
one big shot — a large first pulse is the classic split trigger.

**Harvest day (Thursday ~18:00) is minor, not a centerpiece.** Just avoid a large pulse in the ~2–3 h
before the pick and avoid a surge right after. Otherwise a normal day.

---

## Hardware / integration (the dependency to resolve on resume)

- **Tensiometer → ESP32/ESPHome analog input**, published to HA (native ESPHome API, consistent with
  the climate-2 device, or MQTT). Likely hosted on the valve-controller ESP32-S3 or a dedicated node.
- **Need to confirm:** sensor model & output type (pressure-transducer voltage vs. Watermark
  resistance → different ESPHome wiring/calibration), count, and placement.
- **Placement best practice:** root-zone depth in *representative* pots; ≥2 per zone for
  averaging/redundancy; site Sun Gold and Black Cherry separately if they can be steered separately.
- **Calibration:** field-check kPa readings; tensiometers need priming and can ingest air — plan a
  maintenance/refill check (already in the growth program's weekly checklist).

---

## Home Assistant implementation sketch

- **Sensors:** `sensor.gh_tensiometer_zoneX_kpa` (per-zone average), plus min/max stats for the
  dryback curve.
- **Helpers (`input_number`):** trigger kPa, overnight dryback ceiling, pulse length, drain-% target,
  last-pulse-before-sunset offset — per variety/zone; reuse the existing `input_number.gh_*` pattern.
- **Automation:** pulse when `kPa ≥ trigger` AND before the sunset cutoff AND `gh_automation_enabled`
  AND `gh_watering_ha_enabled`; enforce min interval + max daily volume; keep the existing watchdog
  and `gh_watering_tracker`.
- **Fail-safe:** if the tensiometer is `unavailable`/stale, fall back to the current conservative
  time schedule so plants never strand dry on sensor failure.
- **Dashboard:** kPa gauge, overnight dryback curve, drain %, daily L/plant vs target, next pulse.

## Safety
- Sensor-failure fallback to time-based schedule (feedback loop must never leave plants dry).
- Max daily volume cap + min inter-pulse interval + `gh_water_watchdog` force-off.
- Never let overnight tension exceed the safe ceiling (crack/BER guard).
- Protect early-stage fruit water supply (don't run deep deficit).

## Open decisions (confirm when we resume)
1. **Zone layout / valve mapping** — today watering is a single pump (`switch.plugg_1_vanning`). Can
   Sun Gold and Black Cherry be irrigated/steered separately, or is it one zone? This decides whether
   per-variety triggers are even possible. (The ESPHome valve-controller has 5 zone valves — clarify
   whether they're wired/used for this.)
2. Exact trigger kPa per variety within the program bands, and how far toward "drier" to push for
   generative steering.
3. Tensiometer hardware model + ESPHome config + placement count.
4. Drain-% measurement method (drain trays / lysimeter / periodic manual).

---

## Phased plan

- **Phase 0 (done, 2026-07-01):** research saved; this design parked.
- **Phase 1 (tensiometers installed):** wire + ESPHome + publish kPa to HA; log **~1–2 weeks of
  baseline dryback data**; check how fast the real substrate dries vs the program's kPa bands.
- **Phase 2:** implement trigger-based pulsing + sunset-aware overnight dryback + fail-safe fallback;
  stay conservative (Sun-Gold-wet) at first.
- **Phase 3:** tune toward the mild generative deficit; add drain monitoring; enable per-variety
  steering if zone layout allows. Watch for cracking + BER as the guardrails.
