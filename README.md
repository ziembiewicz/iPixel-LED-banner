# iPixel-LED-banner

An iPixel 96x16 Bluetooth LED panel used as an "on air" sign, driven by Home Assistant.
Set a status in Home Assistant and the panel shows a matching scrolling message, dims at night,
and turns off when the status is cleared.

## How it works

```
Home Assistant ──API──> ESP32-C6 (ESPHome bluetooth_proxy) ──BLE──> iPixel panel
```

- **ESP32-C6** only relays Bluetooth Low Energy traffic, so the panel can sit anywhere in Wi-Fi range.
- **ble_led_pixel** (HACS custom integration) talks the panel's protocol, with local patches.
- **Desired state, not commands:** one script computes what the panel *should* show and pushes it;
  one automation calls it on every relevant event and retries until it succeeds.
- **Meeting detection:** a small PowerShell script on the PC reports when the microphone or the webcam
  is in use; Home Assistant then sets the status to ON AIR and restores the previous one afterwards.
  A status set by hand always wins. See `windows/README.md`.

## Layout

| Path | What it is |
|---|---|
| `esphome/ipixel-proxy.yaml` | ESPHome config for the ESP32-C6 Bluetooth proxy |
| `esphome/secrets.yaml.example` | Secret names the config expects |
| `homeassistant/scripts/ipixel_zastosuj.yaml` | Desired-state script (key `ipixel_zastosuj` in `scripts.yaml`) |
| `homeassistant/automations/ipixel_dyrygent.yaml` | Conductor: triggers, retries, 10-minute self-healing |
| `homeassistant/automations/ipixel_bezpiecznik.yaml` | Status fuse: clears a forgotten status |
| `homeassistant/automations/spotkanie_pc.yaml` | Meeting signal from the PC (webhook, 3-minute dead man's switch) |
| `homeassistant/automations/spotkanie_status.yaml` | Meeting -> ON AIR and back; manual status always wins |
| `homeassistant/helpers/*.yaml` | Reference definitions of the UI helpers |
| `windows/` | Meeting detector for the PC (PowerShell, scheduled task) |
| `patches/ble_led_pixel/` | Patches for the integration (GPL-3.0, see its README) |

Entity IDs assume the panel's entities are renamed to the `ipixel_panel` prefix
(`switch.ipixel_panel`, `text.ipixel_panel_display`, ...).

## Source of truth

This repository is the single source of truth for the panel's configuration. Changes go through
pull requests and are then deployed to Home Assistant and ESPHome; the running setup must match `main`.

## License

MIT (see `LICENSE`), except `patches/ble_led_pixel/`, which is GPL-3.0.
