# Mobile-app push notifications for greenhouse alerts

**Date:** 2026-07-09
**Status:** Approved

## Problem

All greenhouse alerts (overheat, cold, humidity, sensor-offline, roll-up-wall
prompts, watering watchdog) currently reach only the Home Assistant dashboard.
They fire through a single script, `script.gh_notify`, which calls only
`persistent_notification.create`. Nothing is delivered to the phone, so an alert
is invisible unless someone has the HA web UI open.

The Home Assistant Companion app is now installed and registered on the server as
device **"Kim Aleksander Hammer sin iPhone"**, exposing the action
`notify.mobile_app_kim_aleksander_hammer_sin_iphone`.

## Design

Extend the single chokepoint. Add a second action to `gh_notify` in
`configs/homeassistant/scripts.yaml` that also pushes to the phone:

```yaml
gh_notify:
  sequence:
    - service: persistent_notification.create   # unchanged: dashboard
      data:
        title: "{{ title }}"
        message: "{{ message }}"
    - service: notify.mobile_app_kim_aleksander_hammer_sin_iphone
      continue_on_error: true                    # phone hiccup never blocks the dashboard alert
      data:
        title: "{{ title }}"
        message: "{{ message }}"
```

Because every alert automation already calls `script.gh_notify`, this one change
routes all of them to the phone. **No automations are modified.**

### Decisions

- **All alerts go to the phone.** The existing alerts are already curated
  critical events, not noise.
- **Keep the dashboard notification.** Phone delivery is additive; the web UI
  loses nothing.
- **`continue_on_error: true`** on the phone step so a transient failure (device
  renamed, app reinstalled → service name changes) still lets the dashboard
  notification post instead of erroring the automation.
- **No priority / DND-bypass channels** (YAGNI). Can be added later if
  overheat-critical should break through silent mode.

## Deploy & verify

1. `rsync` the updated `scripts.yaml` to `greenhouse:/opt/greenhouse/config/homeassistant/`
   using the authorized key (`~/.ssh/{bitbucket_mb_air_15}`, `IdentitiesOnly=yes`).
   `make deploy-ha` is not used directly because it invokes plain `ssh greenhouse`
   (no IdentityFile configured).
2. Restart Home Assistant (`docker compose restart homeassistant`) so the reloaded
   script takes effect. Input helpers and switch states persist across restart.
3. **End-to-end test:** call `script.gh_notify` once (Developer Tools → Actions)
   and confirm the push arrives on the phone. The service slug is derived from the
   device name, so a successful test is the proof it is exactly right.

## Rollback

Revert the two added lines in `scripts.yaml` and redeploy. No schema/state changes.
