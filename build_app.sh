#!/bin/bash
set -euo pipefail

# =====================================================================
#  Tempest AI macOS App Builder
#  Builds and packages the SwiftUI app + AI learner into a .app
# =====================================================================

cd "$(dirname "$0")"

APP_NAME="Tempest AI"
FINAL_APP_BUNDLE="build/${APP_NAME}.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tempestai-build.XXXXXX")"
trap 'rm -rf "${STAGING_ROOT}"' EXIT
APP_BUNDLE="${STAGING_ROOT}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"
APP_SUPPORT_STATE="${HOME}/Library/Application Support/TempestAI/learner_state.json"

LEARNER_WAS_CLEARED=0
if [ -f "${APP_SUPPORT_STATE}" ]; then
    LEARNER_WAS_CLEARED="$(APP_SUPPORT_STATE="${APP_SUPPORT_STATE}" python3 - <<'PY'
import json
import os
from pathlib import Path

state_path = Path(os.environ["APP_SUPPORT_STATE"])
try:
    state = json.loads(state_path.read_text(encoding="utf-8"))
except Exception:
    print(0)
else:
    cleared = bool(state.get("clearedTrainingFloor"))
    empty = int(state.get("replayCount") or 0) == 0 and int(state.get("trainingSteps") or 0) == 0
    print(1 if cleared and empty else 0)
PY
)"
fi

if [ "${LEARNER_WAS_CLEARED}" = "1" ]; then
    echo "==> Intentional learner reset detected; bundling fresh Swift learner seed…"
fi

echo "==> Cleaning previous build…"
rm -rf build "TempestAI/.build"

# -------------------------------------------------------------------
# 1. Build Swift executable with SPM
# -------------------------------------------------------------------
echo "==> Building Swift executable (release)…"
swift build -c release --package-path . \
    -Xswiftc "-I$(xcrun --show-sdk-path)/usr/lib" \
    -Xlinker "-F$(xcrun --show-sdk-path)/System/Library/Frameworks" \
    || {
    echo "[!] Swift build failed.  Try opening Package.swift in Xcode instead."
    exit 1
}

BIN=".build/arm64-apple-macosx/release/TempestAI"
if [ ! -f "$BIN" ]; then
    BIN=".build/release/TempestAI"
fi
if [ ! -f "$BIN" ]; then
    echo "[!] Could not find built binary."
    exit 1
fi

# -------------------------------------------------------------------
# 2. Create .app bundle structure
# -------------------------------------------------------------------
echo "==> Creating app bundle…"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "$BIN" "${MACOS_DIR}/TempestAI"
cp Info.plist "${APP_BUNDLE}/Contents/"

# Embed entitlements (used during code signing)
cp TempestAI.entitlements "${RES_DIR}/"

# -------------------------------------------------------------------
# 3. Copy self-contained Swift runtime resources
# -------------------------------------------------------------------
echo "==> Bundling Swift ROM runtime resources…"
mkdir -p "${RES_DIR}/models" "${RES_DIR}/roms" \
         "${RES_DIR}/nvram"

# Bundle only Swift-native learned state. Raw PyTorch checkpoints and NumPy
# replay buffers stay in the repo/Application Support for developer conversion
# and recovery, but are not production runtime resources.
if [ -d models/swift_tensors ]; then
    cp -R models/swift_tensors "${RES_DIR}/models/"
fi
if [ -f models/game_settings.json ]; then
    cp models/game_settings.json "${RES_DIR}/models/"
fi

# Always bundle arcade-authentic gameplay settings. Local model checkpoints are
# copied above, but stale training-shortcut settings from older builds must not
# make the packaged app start on advanced levels.
cat > "${RES_DIR}/models/game_settings.json" <<'JSON'
{
  "settings_version": 2,
  "start_advanced": false,
  "start_level_min": 1,
  "epsilon_pct": -1,
  "expert_pct": -1,
  "auto_curriculum": false
}
JSON

RES_MODELS="${RES_DIR}/models" REPO_MODELS="models" LEARNER_WAS_CLEARED="${LEARNER_WAS_CLEARED}" python3 - <<'PY'
import datetime as _dt
import json
import os
from pathlib import Path

models = Path(os.environ["RES_MODELS"])
repo_models = Path(os.environ["REPO_MODELS"])
tensor_manifest = repo_models / "swift_tensors" / "manifest.json"
tensor_metadata = {}
if tensor_manifest.is_file():
    try:
        tensor_metadata = json.loads(tensor_manifest.read_text(encoding="utf-8"))
    except Exception:
        tensor_metadata = {}

cleared = os.environ.get("LEARNER_WAS_CLEARED") == "1"
seed = {
    "version": 3,
    "source": "bundled_reset_seed" if cleared else "bundled_swift_seed",
    "checkpointHash": tensor_metadata.get("checkpoint_sha256"),
    "replayCount": 0,
    "trainingSteps": 0 if cleared else int(tensor_metadata.get("total_training_steps", 0) or 0),
    "optimizerStep": 0,
    "epsilon": 1.0 if cleared else float(tensor_metadata.get("epsilon", 0.01) or 0.01),
    "expertRatio": 0.50 if cleared else float(tensor_metadata.get("expert_ratio", 0.02) or 0.02),
    "trainingEnabled": True,
    "bestAIMode": False,
    "loss": 0.0,
    "gradNorm": 0.0,
    "qMean": 0.0,
    "agreement": 0.0,
    "episodes": 0,
    "clearedTrainingFloor": cleared,
    "savedAt": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
}
(models / "swift_learner_seed.json").write_text(
    json.dumps(seed, indent=2, sort_keys=True),
    encoding="utf-8",
)
print(f"    wrote Swift learner seed (replay {seed['replayCount']:,})")
PY

# Copy only the verified Tempest ROM set used by the Swift loader.
if [ -d roms/tempest1 ]; then
    mkdir -p "${RES_DIR}/roms/tempest1"
    cp -R roms/tempest1/* "${RES_DIR}/roms/tempest1/"
fi

# Copy EAROM seed/storage so the bundled Swift emulator keeps configured
# authentic high-score initials (Tempest stores only three initials, currently
# RCC) without patching the ROM.
if [ -d nvram ]; then
    cp -R nvram/* "${RES_DIR}/nvram/" 2>/dev/null || true
fi

# MLX loads its Metal kernels from a colocated mlx.metallib first, then from
# Contents/Resources/mlx.metallib. SwiftPM builds only produce this file when
# Xcode's Metal toolchain is installed and the MLX shader build step runs.
MLX_METALLIB=""
while IFS= read -r candidate; do
    MLX_METALLIB="${candidate}"
    break
done < <(find .build .build/checkouts/mlx-swift -type f \( -name "mlx.metallib" -o -name "default.metallib" \) 2>/dev/null)

if [ -n "${MLX_METALLIB}" ]; then
    cp "${MLX_METALLIB}" "${MACOS_DIR}/mlx.metallib"
    cp "${MLX_METALLIB}" "${RES_DIR}/mlx.metallib"
    echo "    bundled MLX Metal kernels from ${MLX_METALLIB}"
else
    if command -v cmake >/dev/null 2>&1 \
        && xcrun -find metallib >/dev/null 2>&1 \
        && [ -d .build/checkouts/mlx-swift/Source/Cmlx/mlx ]; then
        echo "    MLX metallib not found; building MLX Metal kernels…"
        cmake -S .build/checkouts/mlx-swift/Source/Cmlx/mlx \
            -B .build/mlx-cmake \
            -DMLX_BUILD_TESTS=OFF \
            -DMLX_BUILD_EXAMPLES=OFF \
            -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build .build/mlx-cmake --target mlx-metallib \
            -j "$(sysctl -n hw.ncpu)" >/dev/null
        while IFS= read -r candidate; do
            MLX_METALLIB="${candidate}"
            break
        done < <(find .build/mlx-cmake -type f -name "mlx.metallib" 2>/dev/null)
    fi

    if [ -n "${MLX_METALLIB}" ]; then
        cp "${MLX_METALLIB}" "${MACOS_DIR}/mlx.metallib"
        cp "${MLX_METALLIB}" "${RES_DIR}/mlx.metallib"
        echo "    bundled MLX Metal kernels from ${MLX_METALLIB}"
    else
        echo "    warning: MLX metallib not found; app will use CPU policy fallback."
        echo "             Install Xcode's Metal Toolchain and rebuild to enable MLX training."
    fi
fi

# -------------------------------------------------------------------
# 4. Set permissions
# -------------------------------------------------------------------
chmod +x "${MACOS_DIR}/TempestAI"

# -------------------------------------------------------------------
# 5. Sign the bundle with a stable bundle identifier
# -------------------------------------------------------------------
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '
            /Developer ID Application:/ { print $2; found=1; exit }
            /Apple Development:/ && dev == "" { dev=$2 }
            END { if (!found && dev != "") print dev }
        ')"
fi
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="-"
fi

echo "==> Signing app bundle (${SIGN_IDENTITY})…"
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
codesign --force --deep --sign "${SIGN_IDENTITY}" \
    --identifier "com.tempest.ai" \
    --entitlements TempestAI.entitlements \
    --timestamp=none \
    "${APP_BUNDLE}"

mkdir -p build
rm -rf "${FINAL_APP_BUNDLE}"
mv "${APP_BUNDLE}" "${FINAL_APP_BUNDLE}"
APP_BUNDLE="${FINAL_APP_BUNDLE}"

# -------------------------------------------------------------------
# 6. Report
# -------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  App bundle created at: ${APP_BUNDLE}"
echo "  Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
echo "  To run: open '${APP_BUNDLE}'"
echo ""
echo "  Self-contained runtime: Swift emulator + Metal renderer"
echo "  Bundled resources: original tempest1 ROMs, models, EAROM"
echo "  No Python, MAME, Lua, sockets, or ScreenCaptureKit are bundled."
echo "=========================================="
