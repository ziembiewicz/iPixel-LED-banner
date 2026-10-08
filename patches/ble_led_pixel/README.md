# Local patches for ble_led_pixel

Patches for the [ble_led_pixel](https://github.com/sphings79/ha-ble-led-pixel-display) Home Assistant
custom integration, applied on top of release **v2.3.3**.

| Patch | What it fixes |
|---|---|
| `0001-text-sendplan.patch` | Text longer than 512 bytes and custom fonts (send plan for long text frames). |
| `0002-set-orientation.patch` | New service `ble_led_pixel.set_orientation` (0/1/2/3 = 0°/90°/180°/270°). The panel forgets its orientation after a power cut, so the desired-state script sends it on every apply. |

Apply from the root of a v2.3.3 checkout:

```sh
git apply /path/to/patches/ble_led_pixel/0001-text-sendplan.patch
git apply /path/to/patches/ble_led_pixel/0002-set-orientation.patch
```

Then copy `custom_components/ble_led_pixel/` to `/config/custom_components/` and restart Home Assistant.
A HACS update overwrites the integration and drops these patches: re-apply them, or drop a
patch once the same fix lands upstream.

## Tests

```sh
pip install pytest
IPIXEL_INTEGRATION_DIR=custom_components/ble_led_pixel python3 -m pytest tests/
```

## License

ble_led_pixel is licensed under GPL-3.0, and these patches are derived from it, so this
directory is licensed under **GPL-3.0** (see `LICENSE` here). The rest of the repository is MIT.
