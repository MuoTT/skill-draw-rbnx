#!/usr/bin/env bash
# Build phase: generate gRPC stubs for the consumed plotter primitive and
# MCP dataclasses for this skill's public tools.
#
# The package is pure Python. The only build-time concern is rbnx codegen:
#   * plotter_pb2 / robonix_contracts_pb2_grpc   (primitive client)
#   * plot_mcp      (Config/RenderPreview[GenerateImage IDL]/DrawScene/DrawPrompt/DrawImage/ListImages)
#   * lifecycle_pb2 and atlas codegen             (Skill.run runtime)
set -euo pipefail
PKG="${RBNX_PACKAGE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="$(cd "$PKG/../../.." && pwd)"
cd "$PKG"

CLEAN="${RBNX_BUILD_CLEAN:-}"
if [[ "$CLEAN" == "1" ]]; then
    echo "[xyz_draw/build] clean: removing rbnx-build/"
    rm -rf rbnx-build
fi
mkdir -p rbnx-build

# Deployment-wide uv environment (shared by the primitive and both skills).
bash "$ROOT/scripts/uv_sync.sh"

# The image pipeline imports the SDK package, whose __init__ pulls in
# numpy + Pillow.
if ! "$ROOT/.venv/bin/python" -c "import numpy, PIL" 2>/dev/null; then
    echo "[xyz_draw/build] ERR: numpy/Pillow missing from $ROOT/.venv." >&2
    echo "                   Run: uv sync --project $ROOT --locked" >&2
    exit 2
fi

# The skill imports the repository SDK (image/trajectory) instead of
# vendoring the geometry code. Fail early if it cannot be found.
if [[ -n "${ROBONIX_XYZ_SDK:-}" ]]; then
    SDK_ROOT="$ROBONIX_XYZ_SDK"
else
    SDK_ROOT="$PKG/../../../SDK"
fi
if [[ ! -f "$SDK_ROOT/robonix_sdk/image.py" ]]; then
    echo "[xyz_draw/build] ERR: Robonix XYZ SDK not found at $SDK_ROOT" >&2
    echo "                   Set ROBONIX_XYZ_SDK to the SDK directory." >&2
    exit 2
fi
echo "[xyz_draw/build] SDK: $SDK_ROOT"

# Generate with the deployment venv so the gencode matches the grpcio/protobuf
# pins that start.sh runs with (see pyproject.toml).
export RBNX_CODEGEN_PYTHON="$ROOT/.venv/bin/python"

FLAGS=(--out-dir "$PKG/rbnx-build/codegen" --mcp)
[[ "$CLEAN" == "1" ]] && FLAGS+=(--clean)

echo "[xyz_draw/build] rbnx codegen ${FLAGS[*]}"
rbnx codegen -p "$PKG" "${FLAGS[@]}"

touch "$PKG/rbnx-build/.rbnx-built"
echo "[xyz_draw/build] done."