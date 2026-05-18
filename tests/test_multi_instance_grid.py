import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def test_swift_runtime_publishes_frames_for_all_games():
    source = (
        ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift"
    ).read_text(encoding="utf-8")
    assert "var updatedFrames: [Int: GameFrameData] = [:]" in source
    assert "updatedFrames[snapshot.clientID]" in source
    assert "publish(status: haltStatus, frames: updatedFrames)" in source


def test_add_and_remove_game_controls_are_exposed():
    controller = (ROOT / "TempestAI" / "TempestRuntimeController.swift").read_text(
        encoding="utf-8"
    )
    control_panel = (ROOT / "TempestAI" / "ControlPanelView.swift").read_text(
        encoding="utf-8"
    )
    game_grid = (ROOT / "TempestAI" / "GameGridView.swift").read_text(
        encoding="utf-8"
    )
    swift_runtime = (
        ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift"
    ).read_text(encoding="utf-8")

    assert 'bridge.sendCommand("add_instance")' in control_panel
    assert "Remove this game" in game_grid
    assert "bridge.removeGame(clientID:" in game_grid
    assert 'sendCommand("remove_instance", params: ["client_id": clientID])' in controller
    assert 'case "remove_instance"' in controller
    assert "func removeLastInstance()" in swift_runtime
    assert "func removeInstance(clientID: Int)" in swift_runtime


def test_selected_tile_removal_maps_client_id_to_swift_instance():
    controller = (ROOT / "TempestAI" / "TempestRuntimeController.swift").read_text(
        encoding="utf-8"
    )
    swift_runtime = (
        ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift"
    ).read_text(encoding="utf-8")

    assert 'params["client_id"] as? Int' in controller
    assert "swiftRuntime.removeInstance(clientID: clientID)" in controller
    assert "$0.machine.clientID == clientID" in swift_runtime


def test_swift_grid_layout_math_for_one_to_twelve_clients(tmp_path):
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        pytest.skip("swiftc not available")

    main = tmp_path / "main.swift"
    main.write_text(
        textwrap.dedent(
            """
            import Foundation

            let expected: [(Int, Int, Int)] = [
                (0, 0, 0),
                (1, 1, 1),
                (2, 2, 1),
                (3, 2, 2),
                (4, 2, 2),
                (5, 3, 2),
                (6, 3, 2),
                (7, 3, 3),
                (8, 3, 3),
                (9, 3, 3),
                (10, 4, 3),
                (11, 4, 3),
                (12, 4, 3),
            ]

            for (count, columns, rows) in expected {
                let actual = GameGridLayout.dimensions(for: count)
                if actual.columns != columns || actual.rows != rows {
                    print("bad dimensions for \\(count): \\(actual)")
                    exit(1)
                }
            }
            """
        )
    )
    output = tmp_path / "grid-layout-test"
    subprocess.run(
        [
            swiftc,
            str(ROOT / "TempestAI" / "GameGridLayout.swift"),
            str(main),
            "-o",
            str(output),
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    subprocess.run([str(output)], check=True, text=True, capture_output=True)


def test_swift_game_frame_decodes_arcade_life_and_high_score_fields(tmp_path):
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        pytest.skip("swiftc not available")

    main = tmp_path / "main.swift"
    main.write_text(
        textwrap.dedent(
            r'''
            import Foundation

            let json = """
            {
              "client_id": 4,
              "frame": 99,
              "score": 12345,
              "high_score": 54321,
              "high_score_initials": "RCC",
              "level": 1,
              "display_level": 1,
              "rom_level_index": 0,
              "geometry_level_index": 0,
              "gamestate": 18,
              "done": true,
              "life_lost": true,
              "game_over": false,
              "lives": 2,
              "fps": 60.0,
              "renderer": "mame_vector",
              "vector_width": 581,
              "vector_height": 571,
              "vector_lines": [
                {
                  "x0": 0.0,
                  "y0": 10.9375,
                  "x1": 5.0,
                  "y1": 10.9375,
                  "argb": 4294964211,
                  "intensity": 192
                }
              ],
              "open_level": false,
              "player_lane": 3.0,
              "player_alive": false,
              "player_depth": 0.0,
              "superzapper_uses": 1,
              "remaining_shots": 7,
              "tube_angles": [],
              "spikes": [],
              "enemies": [],
              "player_shots": [],
              "enemy_shots": []
            }
            """.data(using: .utf8)!

            let frame = try JSONDecoder().decode(GameFrameData.self, from: json)
            guard frame.clientID == 4,
                  frame.score == 12345,
                  frame.highScore == 54321,
                  frame.highScoreInitials == "RCC",
                  frame.lifeLost,
                  !frame.gameOver,
                  frame.lives == 2,
                  frame.displayLevel == 1,
                  frame.romLevelIndex == 0,
                  frame.renderer == "mame_vector",
                  frame.vectorWidth == 581,
                  frame.vectorLines.count == 1,
                  frame.vectorLines[0].x1 == 5.0,
                  frame.vectorLines[0].argb == 4294964211 else {
                exit(1)
            }
            '''
        )
    )
    output = tmp_path / "frame-decode-test"
    subprocess.run(
        [
            swiftc,
            str(ROOT / "TempestAI" / "GameFrameData.swift"),
            str(main),
            "-o",
            str(output),
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    subprocess.run([str(output)], check=True, text=True, capture_output=True)


def test_swift_avg_vector_output_is_the_default_renderer_path():
    renderer = (ROOT / "TempestAI" / "GameDisplayView.swift").read_text(
        encoding="utf-8"
    )
    runtime = "\n".join(
        [
            (ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift").read_text(
                encoding="utf-8"
            ),
            (
                ROOT / "TempestAI" / "Emulator" / "TempestEmulatorTypes.swift"
            ).read_text(encoding="utf-8"),
        ]
    )

    assert "if frame.vectorLines.isEmpty" in renderer
    assert "drawROMVectors" in renderer
    assert "ROMVectorViewport" in renderer
    assert "lines: [GameVectorLineData]" in renderer
    assert "renderer: frame.renderer" in renderer
    assert '"swift_avg_vector"' in runtime
    assert 'renderer == "swift_avg_vector"' in renderer
    assert "pinned to the device bounds" in renderer
    assert 'renderer == "mame_vector"' in renderer
    assert "CGPoint(x: y, y: rawWidth - x)" in renderer
    assert "CGPoint(x: x, y: y)" in renderer
    assert "contentWidth + (padding * 2.0)" in renderer
    assert "Double(display.x) - minX" in renderer
    assert "Double(display.y) - minY" in renderer
    assert "isPointVector" in renderer
    assert "Path(ellipseIn: rect)" in renderer
    assert "drawSyntheticFallback" in renderer
