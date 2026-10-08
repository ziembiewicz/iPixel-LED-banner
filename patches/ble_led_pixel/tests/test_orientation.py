"""Orientation frame built by 0002-set-orientation.patch.

Expected values are written by hand from the protocol (pypixelcolor set_orientation:
05 00 06 80 <n>), not computed with the library: a parity test of two
implementations would pass even if both were wrong in the same way.

Run: IPIXEL_INTEGRATION_DIR=<patched custom_components/ble_led_pixel> \
     python3 -m pytest test_orientation.py
"""
import importlib.util
import os
from pathlib import Path

import pytest

_DIR = Path(os.environ["IPIXEL_INTEGRATION_DIR"])
_spec = importlib.util.spec_from_file_location("commands", _DIR / "device" / "commands.py")
commands = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(commands)


@pytest.mark.parametrize(
    "orientation, frame",
    [
        (0, "0500068000"),
        (1, "0500068001"),
        (2, "0500068002"),  # 180° — ustawienie tabliczki na drzwiach
        (3, "0500068003"),
    ],
)
def test_frame_matches_protocol(orientation, frame):
    assert commands.make_orientation_command(orientation).hex() == frame


@pytest.mark.parametrize("bad", [-1, 4, 255])
def test_out_of_range_rejected(bad):
    with pytest.raises(ValueError):
        commands.make_orientation_command(bad)
