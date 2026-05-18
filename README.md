# Tempest AI

Self-contained macOS Swift/Metal/MLX Tempest AI app.

![Tempest AI running one Swift ROM game](docs/media/tempest-ai-single-game.png)

## Demo

The app runs the original `tempest1` ROM inside the macOS window with the Swift
emulator, Swift AVG vector renderer, and MLX/Metal AI runtime. No MAME window,
Python backend, Lua bridge, sockets, ScreenCaptureKit, or external game process
is used by the normal app runtime.

<video src="docs/media/tempest-ai-demo.mp4" controls width="100%"></video>

[Watch the short MP4 demo](docs/media/tempest-ai-demo.mp4)

![Tempest AI four-game training grid](docs/media/tempest-ai-four-games.png)

## System Graphs

### Runtime Architecture

```mermaid
flowchart LR
    User["Player or operator"] --> UI["SwiftUI controls"]
    UI --> Runtime["TempestRuntimeController"]

    Runtime --> GameGrid["Equal game grid"]
    Runtime --> Learner["Shared MLX Rainbow learner"]
    Runtime --> Store["Application Support persistence"]

    subgraph GameInstance["Each active game"]
        Machine["TempestMachine"]
        CPU["Swift MOS 6502"]
        Bus["Tempest memory map"]
        AVG["Swift Atari AVG"]
        ROM["Original tempest1 ROM bytes"]
        EAROM["EAROM high scores"]
        AgentState["195-value AI state"]
        Machine --> CPU
        CPU --> Bus
        Bus --> ROM
        Bus --> EAROM
        Bus --> AVG
        Bus --> AgentState
    end

    Runtime --> Machine
    AVG --> Vectors["Vector line frame"]
    Vectors --> Metal["Metal vector renderer"]
    Metal --> GameGrid

    AgentState --> Learner
    Learner --> Actions["44-action policy"]
    Actions --> Machine
```

### Learning Loop

```mermaid
sequenceDiagram
    participant G as Swift game instances
    participant P as MLX policy
    participant R as Shared prioritized replay
    participant L as MLX learner
    participant S as Saved learner state

    G->>P: Batch current 195-value states
    P-->>G: Greedy or exploratory 44-action choices
    G->>G: Step original ROM emulator
    G->>R: Store state, action, reward, next state, done
    R->>L: Sample prioritized n-step batches
    L->>L: C51 projection and Double-DQN target
    L->>P: Update online network weights
    L->>R: Update sample priorities
    L->>P: Sync target network periodically
    L->>S: Save weights, optimizer, replay metadata
```

### Self-Contained App Boundary

```mermaid
flowchart TB
    subgraph Bundle["Tempest AI.app bundle"]
        SwiftApp["Swift app binary"]
        ROMs["roms/tempest1"]
        Tensors["models/swift_tensors"]
        MetalLib["MLX Metal kernels"]
    end

    subgraph RuntimeData["~/Library/Application Support/TempestAI"]
        LearnedWeights["Learned weights"]
        ReplayMeta["Replay metadata"]
        HighScores["EAROM high scores"]
        Settings["AI and arcade settings"]
    end

    Bundle --> Run["Normal app runtime"]
    RuntimeData --> Run
    Run --> Output["Single macOS app window"]

    External["Python, MAME, Lua, sockets, ScreenCaptureKit"] -. "not used at runtime" .-> Run
```

### Multi-Game Training

```mermaid
flowchart LR
    Add["Add Game"] --> Instances["1 to N Swift ROM instances"]
    Instances --> Grid["Dynamic equal grid"]
    Instances --> Replay["One shared replay memory"]
    Replay --> Brain["One shared MLX brain"]
    Brain --> PolicyBatch["Batched policy actions"]
    PolicyBatch --> Instances
    Instances --> Metrics["Unified learning and arcade metrics"]
    Metrics --> Sidebar["Readable sidebar status"]
```

## Current Runtime

The current app lives in `TempestAI/` and runs without external game processes:

- Original `tempest1` ROM bytes from `roms/tempest1/`
- Swift 6502 and Atari Tempest hardware emulation
- Swift AVG vector output rendered by Metal
- MLX/Metal Rainbow-style AI inference and learning
- App data, learned state, and high-score persistence under
  `~/Library/Application Support/TempestAI/`

The normal app runtime does not bundle or launch Python, MAME, Lua, sockets, or
ScreenCaptureKit.

## Build And Run

```sh
./build_app.sh
open "build/Tempest AI.app"
```

The current app bundle is created at `build/Tempest AI.app`.

## Active Project Layout

```text
TempestAI/                  Swift app, emulator, Metal renderer, MLX learner
docs/media/                 README screenshots and demo video
models/swift_tensors/       Swift-readable neural tensor package
roms/tempest1/              Original Tempest ROM set used by the Swift emulator
tests/                      Current Swift-runtime and cleanup regression tests
build_app.sh                Release build and app-bundle script
```

## Verification

Run the current static/runtime checks:

```sh
python3 -m pytest -q
swift build -c release --package-path .
./build_app.sh
```

## Credits

Thanks to Dave Plummer and the original `davepl/ArcadeAI` project for the
Tempest AI research foundation, original Python/Lua/MAME training system, and
reference implementation that made this Swift/Metal evolution possible.
