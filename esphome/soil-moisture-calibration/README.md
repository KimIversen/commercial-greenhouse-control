# Capacitive Soil Moisture Sensor Calibration Procedure
## For Peat Moss / Wood Fiber Substrate (50/50 mix) — ESP32‑C3 (Seeed XIAO)

This guide shows how to calibrate low‑cost **capacitive** moisture probes to report **Volumetric Water Content (VWC, % by volume)** that matches your **actual pot packing** and fertigation conditions.

> **Key principles**
> - **Calibrate at the same bulk density/packing used in your pots**, not “as tight as possible.” Dielectric sensors respond to the mix of water/air/solids around the probe; packing changes porosity and therefore the reading.
> - Use **points that matter operationally** for tomatoes in peat/wood fiber: **0%, 30%, 45%, 60% VWC** (≈ dry → trigger → mid‑range → container capacity).
> - Match **EC and temperature** to your real system during calibration (use your fertigation solution if possible).

---

## Equipment Needed
- XIAO ESP32‑C3 flashed with **Calibration YAML** (3 sensors)
- 3× capacitive soil moisture sensors (v2.0 style)
- Fresh, **oven‑dry** substrate sample (50/50 peat : wood fiber)
- Distilled/RO water or your **fertigation solution** (preferred)
- Graduated cylinders or scale (0.1 g precision) and mixing tub (≥2–3 L)
- Beakers or containers for **packed calibration volume** (≥1 L)
- Timer and marker (to mark probe depth)

---

## Pre‑Calibration Setup
1. **Wire the probes to ADC‑capable pins** on the XIAO ESP32‑C3: use **GPIO2 (A0), GPIO3 (A1), GPIO4 (A2)**.  
   *(Avoid GPIO5 if possible; it’s an ADC2 pin and can conflict with Wi‑Fi.)*
2. **Flash the calibration firmware** (updated YAML) with:
   - `attenuation: 12db` on each `adc` sensor
   - `raw: true` on each `adc` sensor (so you see 0–4095 counts)
   - `web_server:` enabled (optional `auth:` recommended)
   - `ota:` includes `- platform: esphome` and (optional) `- platform: web_server`
3. **Open the device web UI** (e.g., `http://soil-calibration.local/`) or Home Assistant device page.
4. **Verify all three sensors** show changing **raw ADC** values and **VWC** readings.

---

## Choosing the Packed Volume (Bulk Density)
- **Pack the substrate exactly as you do in your pots** (same compression/handling). Measure the **packed volume** you’ll use for each calibration batch (e.g., **750 mL** for ~90 g dry in your system).  
- Use that **in‑situ packed volume** for all VWC calculations in this guide.

> **Quick water calculation:**  
> Water to add (mL or g) = **Target VWC (%) × Packed Volume (mL) ÷ 100**

**Example (your pots):** 90 g dry occupies **750 mL**  
→ 30% = **225 mL**, 45% = **337.5 mL**, 60% = **450 mL**

---

## Calibration Procedure — VWC Method (0 / 30 / 45 / 60 %)
Calibrate all three probes **in the same batch** if possible. Insert probes **vertically**, to a **marked depth**, avoiding wall contact.

### Materials
- Dry substrate (oven‑dried at **105 °C for 24 h**, then cooled in a sealed container)
- Graduated cylinder(s) or a scale
- Water or fertigation solution at room temperature
- Mixing tub and a container you can pack to your **chosen volume** (e.g., 750 mL)

### Step A — 0% VWC (Dry)
1. **Pack dry substrate** to your selected volume (e.g., **750 mL**).  
2. **Insert probes** at consistent depth; tamp lightly around blades to remove air gaps.  
3. Wait **1–2 min** for readings to stabilize.  
4. Click **“Calibrate ALL → 0% VWC (dry)”** in the device UI.

### Step B — 30% VWC
1. **Calculate and add water:** `0.30 × Volume` (e.g., **225 mL** for 750 mL).  
2. **Hydrate gradually** (peat/wood fiber can be hydrophobic): add in 2–3 increments, mixing thoroughly.  
3. **Equilibrate** 20–60 min; mix once or twice during equilibration.  
4. Insert probes (same depth/positions), wait to stabilize, then click **“Calibrate ALL → 30% VWC.”**

### Step C — 45% VWC
1. From a fresh **dry** packed batch (same volume), add **0.45 × Volume** (e.g., **337.5 mL**).  
2. Mix thoroughly, equilibrate, re‑insert probes, stabilize, then click **“Calibrate ALL → 45% VWC.”**

### Step D — 60% VWC (Container Capacity)
1. From a fresh **dry** packed batch (same volume), add **0.60 × Volume** (e.g., **450 mL**).  
2. Mix very thoroughly. If **free water pools** or the mix won’t absorb uniformly, your **true container‑capacity VWC** at this packing may be **< 60%**.  
   - Alternative: **Saturate fully**, then **freely drain 30–60 min**; weigh to compute the actual VWC and use that as your top point.  
3. Insert probes, stabilize, then click **“Calibrate ALL → 60% VWC.”**

> **Direction check:** Most low‑cost capacitive probes show **higher raw counts when dry** and **lower counts when wet**. If yours behave oppositely, flip the comparison logic in the YAML (noted in comments).

---

## Verifying the VWC (Optional but Recommended)
Two ways to confirm the target VWC you mixed:

### 1) Gravimetric check (by mass)
- Take a small sub‑sample (e.g., **100 g** wet), weigh **Ww**.  
- Oven‑dry 24 h at 105 °C, weigh **Wd**.  
- Gravimetric water content \( \theta_g \) = \( (Ww - Wd) / Wd \) (g/g).  
- Convert to VWC (approx.): \( \theta_v \approx \theta_g \times \rho_b \), where \( \rho_b \) is bulk density (g/mL).

### 2) Volumetric check (by volume)
- If your sub‑sample volume is known (mL), then  
  **VWC% = ((Ww – Wd) / Volume_mL) × 100** (using 1 g ≈ 1 mL for water).

---

## Commercial Tomato VWC Targets (Peat/Wood Fiber, High Tunnel)
Use these as **operational setpoints** once the probes are calibrated.

| Growth Stage | Typical VWC Range | Start Irrigation | Stop Irrigation | Notes |
|---|---|---|---|---|
| **Seedlings / Transplants** | **55–65%** | 55% | 65% | Keep very moist for establishment. |
| **Vegetative (pre‑flower)** | **45–60%** | 45% | 60% | Steady growth; avoid drybacks < 40%. |
| **Flowering & Fruit Set** | **40–55%** | 40% | 55% | Consistent moisture supports Ca uptake; helps prevent BER. |
| **Fruit Filling** | **40–50%** | 40% | 50% | Higher water demand; maintain consistency. |
| **Ripening / Harvest** | **35–50%** | 35% | 45% | Mild dry‑down can improve flavor; avoid big swings. |

**Critical thresholds (Sun Gold / cherry types):**
- **Container capacity:** ~**58–60% VWC** (after full saturation + free drainage).  
- **Do not exceed:** **~60%** for long periods (keep air space).  
- **Standard trigger:** **~40–45%**.  
- **Mild stress:** **~35%** (use cautiously for flavor).  
- **Avoid:** **< 30%** (drought stress → yield loss, cracking on re‑wet).

---

## Programming Automated Irrigation (example concept)
Use **frequent, small fertigations** to hold a band (e.g., **45–58%** during fruiting). Add hysteresis and a minimum off‑time.

```yaml
# Home Assistant example (concept)
automation:
  - alias: "Tomato Irrigation — Fruiting"
    trigger:
      - platform: numeric_state
        entity_id: sensor.greenhouse_vwc_avg
        below: 45        # start threshold
    condition: []
    action:
      - service: switch.turn_on
        target: { entity_id: switch.irrigation_zone_1 }
      - delay: "00:03:00"   # run time per pulse; tune to flow/volume
      - service: switch.turn_off
        target: { entity_id: switch.irrigation_zone_1 }
  - alias: "Tomato Irrigation — Stop Above Band"
    trigger:
      - platform: numeric_state
        entity_id: sensor.greenhouse_vwc_avg
        above: 58        # stop threshold
    action:
      - service: switch.turn_off
        target: { entity_id: switch.irrigation_zone_1 }
```

> Consider day/night schedules and **climate‑aware adjustments** (e.g., higher band on very hot/dry days; lower band on cool/humid days).

---

## Calibration Data Log (print & fill)
```
Calibration Date: ___________     Substrate Batch: ___________
Packed Volume per batch (mL): ____     Bulk Density (g/mL): ____

VWC Calibration Points (raw ADC counts)
           | Sensor 1 | Sensor 2 | Sensor 3 |
-----------|----------|----------|----------|
0% VWC     | ________ | ________ | ________ |
30% VWC    | ________ | ________ | ________ |
45% VWC    | ________ | ________ | ________ |
60% VWC    | ________ | ________ | ________ |

Verification (optional)
30% VWC target: ____ mL added; Check: ____ %
45% VWC target: ____ mL added; Check: ____ %
60% VWC target: ____ mL added; Check: ____ %
```

---

## Troubleshooting
- **Sensors disagree >±5–10%:** Re‑pack uniformly; remove air gaps; ensure probes aren’t touching container walls; verify wiring and noise.  
- **Readings drift over days/weeks:** Clean salt/algae buildup; check EC/temperature; substrate decomposition over time can change dielectric properties → consider seasonal re‑calibration.  
- **Non‑linear response:** Normal for low‑cost capacitive probes → multi‑point calibration (this guide) is the remedy.  
- **Top point pools water:** Your true container capacity at that packing is < 60% → use the **saturated & freely drained** point as your 100% reference for that top calibration.

---

## ESPHome Notes (current as of July 2025)
- Use **`attenuation: 12db`** (not `11dB`).  
- Keep **`raw: true`** on ADC sensors if your math uses counts (0–4095).  
- XIAO ESP32‑C3 analogs: **GPIO2/3/4** (ADC1). Avoid **GPIO5** unless you’ve tested with Wi‑Fi.  
- Virtual calibration buttons appear in both the **web UI** and **Home Assistant** (no physical button required).  
- If using web‑page firmware uploads on new ESPHome builds, add `ota: - platform: web_server` and protect the **web_server** with `auth:`.

---

## Quick Reference — Water to Add (for your example)
**Packed volume = 750 mL**; targets and additions:
- **30% VWC:** **225 mL** (≈225 g)  
- **45% VWC:** **337.5 mL** (≈338 g)  
- **60% VWC:** **450 mL** (≈450 g)

> Formula to scale: **Water (mL) = Target% × Packed Volume (mL) ÷ 100**

