#!/usr/bin/env python3
"""Native renderer must keep the calibrated Atari Tempest web geometry tables."""

from __future__ import annotations

import pathlib
import re
import hashlib


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SWIFT_RENDERER = REPO_ROOT / "TempestAI" / "GameDisplayView.swift"
VIEWPORT_CONFIG = REPO_ROOT / "TempestAI" / "TempestVectorViewportConfig.swift"
TABLE_HASHES = {
    "levelX": "93ed5e1c114adb1eb6afc4e791718447af12b49b4770bd7695274ab6d2546d83",
    "levelY": "b0e0dd8ec4629a80f532e0c51b515597e73657375be5861c2517a1419aeb64e2",
    "levelRemap": "ca78609880a6401fa23363956740fb21ab8c6dd80da039c1a6262b1e54d17108",
    "levelOpen": "9fbdb4c5e4d3d7667b614378d3f7bdb0aa3295750fa46a7aa30c80390891338a",
}


def _swift_hex_array(name: str) -> list[int]:
    text = SWIFT_RENDERER.read_text(encoding="utf-8")
    match = re.search(
        rf"private static let {name}: \[[^\]]+\] = \[(.*?)\]",
        text,
        re.DOTALL,
    )
    assert match, f"missing Swift array {name}"
    return [int(v, 16) for v in re.findall(r"0x([0-9A-Fa-f]{2})", match.group(1))]


def _swift_bool_array(name: str) -> list[bool]:
    text = SWIFT_RENDERER.read_text(encoding="utf-8")
    match = re.search(
        rf"private static let {name}: \[Bool\] = \[(.*?)\]",
        text,
        re.DOTALL,
    )
    assert match, f"missing Swift bool array {name}"
    return [v == "true" for v in re.findall(r"\b(true|false)\b", match.group(1))]


def _hash_bytes(values: list[int]) -> str:
    return hashlib.sha256(bytes(values)).hexdigest()


def test_native_renderer_tables_keep_calibrated_tempest_geometry():
    assert _hash_bytes(_swift_hex_array("levelX")) == TABLE_HASHES["levelX"]
    assert _hash_bytes(_swift_hex_array("levelY")) == TABLE_HASHES["levelY"]
    assert _hash_bytes(_swift_hex_array("levelRemap")) == TABLE_HASHES["levelRemap"]
    assert (
        _hash_bytes([1 if value else 0 for value in _swift_bool_array("levelOpen")])
        == TABLE_HASHES["levelOpen"]
    )


def test_native_renderer_has_all_16_webs_and_lanes():
    assert len(_swift_hex_array("levelX")) == 16 * 16
    assert len(_swift_hex_array("levelY")) == 16 * 16
    assert len(_swift_hex_array("levelRemap")) == 16
    assert len(_swift_bool_array("levelOpen")) == 16


def test_swift_avg_vector_transform_is_upright_and_stable():
    renderer = SWIFT_RENDERER.read_text(encoding="utf-8")

    assert 'renderer == "swift_avg_vector"' in renderer
    assert 'renderer == "mame_vector"' in renderer
    assert "return CGPoint(x: x, y: y)" in renderer
    assert "return CGPoint(x: rawHeight - y, y: x)" not in renderer
    assert "return CGPoint(x: x, y: rawHeight - y)" not in renderer


def test_swift_avg_uses_dedicated_viewport_for_correct_scale():
    machine = (REPO_ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift").read_text(
        encoding="utf-8"
    )
    types = (
        REPO_ROOT / "TempestAI" / "Emulator" / "TempestEmulatorTypes.swift"
    ).read_text(encoding="utf-8")
    renderer = SWIFT_RENDERER.read_text(encoding="utf-8")
    metal_renderer = (
        REPO_ROOT / "TempestAI" / "MetalVectorDisplayView.swift"
    ).read_text(encoding="utf-8")
    viewport_config = VIEWPORT_CONFIG.read_text(encoding="utf-8")
    bridge = (REPO_ROOT / "TempestAI" / "TempestRuntimeController.swift").read_text(
        encoding="utf-8"
    )

    assert "vectorWidth: 581" in machine
    assert "vectorHeight: 571" in machine
    assert "vectorWidth: 581" in types
    assert "vectorHeight: 571" in types
    assert "TempestVectorViewportConfig.swiftAVG()" in renderer
    assert "TempestVectorViewportConfig.swiftAVG()" in metal_renderer
    assert "if let swiftAVGConfig" in renderer
    assert "if let swiftAVGConfig" in metal_renderer
    assert "swiftAVGObservedBounds" not in metal_renderer
    assert "existing.union(raw)" not in metal_renderer
    assert '} else if renderer == "mame_vector" {' in renderer
    assert '} else if renderer == "mame_vector" {' in metal_renderer
    assert "defaultCenterX = 290.5" in viewport_config
    assert "defaultCenterY = 285.5" in viewport_config
    assert "defaultViewportWidth = 581.0" in viewport_config
    assert "defaultViewportHeight = 571.0" in viewport_config
    assert "TEMPEST_SWIFT_AVG_CENTER_X" in viewport_config
    assert "TEMPEST_SWIFT_AVG_CENTER_Y" in viewport_config
    assert "TEMPEST_SWIFT_AVG_VIEWPORT_WIDTH" in viewport_config
    assert "TEMPEST_SWIFT_AVG_VIEWPORT_HEIGHT" in viewport_config
    assert "didLogSwiftAVGViewport" in bridge
    assert "Swift AVG bounds x=%.1f..%.1f y=%.1f..%.1f viewport center=%.1f,%.1f size=%.1fx%.1f" in bridge


def test_metal_renderer_uses_thin_single_pass_vector_lines():
    metal_renderer = (
        REPO_ROOT / "TempestAI" / "MetalVectorDisplayView.swift"
    ).read_text(encoding="utf-8")
    canvas_renderer = SWIFT_RENDERER.read_text(encoding="utf-8")

    assert "private struct MetalVectorLineKey: Hashable" in metal_renderer
    assert "var seenLines = Set<MetalVectorLineKey>()" in metal_renderer
    assert "guard seenLines.insert(lineKey).inserted else" in metal_renderer
    assert "(input.width * 0.5) + 0.65" in metal_renderer
    assert "input.dotRadius + 0.65" in metal_renderer
    assert "halfWidth + 0.65" in metal_renderer
    assert "min(0.78, min(drawableSize.width, drawableSize.height) * 0.00055)" in metal_renderer
    assert "max(0.55, lineWidth * 0.95)" in metal_renderer
    assert "min(0.70, min(size.width, size.height) * 0.00055)" in canvas_renderer
