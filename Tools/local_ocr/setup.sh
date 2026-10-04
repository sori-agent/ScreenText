#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .local/huggingface

# Keep Python, model weights, and build products inside this checkout.
command -v uv >/dev/null || { echo "Install uv first: https://docs.astral.sh/uv/getting-started/installation/" >&2; exit 1; }
if [[ ! -x .venv/bin/python ]]; then
    uv venv --python 3.12 .venv
fi
uv pip install --python .venv/bin/python -r Tools/local_ocr/requirements.txt
HF_HOME="$PROJECT_DIR/.local/huggingface" HF_HUB_DISABLE_XET=1 .venv/bin/python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download("PaddlePaddle/PaddleOCR-VL-1.6",
    revision="c5630abae1d940eafe0697512a0325494b02ab42",
    allow_patterns=["*.json", "*.jsonl", "*.safetensors", "*.py", "*.model", "*.tiktoken", "*.txt", "*.jinja"])
PY
swiftc -O Tools/local_ocr/DetectLines.swift -o .local/detect-lines
xcodebuild -project TRex.xcodeproj -scheme TRex -configuration Debug \
    -derivedDataPath .local/DerivedData -jobs 2 -skipMacroValidation \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build > .local/app-build.log 2>&1 || {
    tail -60 .local/app-build.log >&2
    exit 1
}
.venv/bin/python Tools/local_ocr/sign_app.py
echo "Built ScreenText. Run Tools/local_ocr/start.sh."
