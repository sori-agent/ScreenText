#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$PROJECT_DIR/.local/DerivedData/Build/Products/Debug/ScreenText.app"
SERVER_PATH="$PROJECT_DIR/Tools/local_ocr/server.py"
PID_FILE="$PROJECT_DIR/.local/server.pid"
MODEL="PaddlePaddle/PaddleOCR-VL-1.6"
PREFS="com.sori.ScreenText.preferences"
cd "$PROJECT_DIR"
[[ -d "$APP_PATH" && -x .local/detect-lines && -x .venv/bin/python ]] || {
    echo "Run Tools/local_ocr/setup.sh first." >&2; exit 1;
}

# Restart only this checkout's GUI so it reads the launcher's preferences afresh.
while read -r APP_PID; do
    APP_COMMAND="$(ps -p "$APP_PID" -o command= 2>/dev/null || true)"
    if [[ "$APP_COMMAND" == "$APP_PATH/Contents/MacOS/ScreenText"* ]]; then
        kill "$APP_PID"
        for attempt in {1..30}; do
            if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$APP_PID" 2>/dev/null; then
            echo "ScreenText did not quit. Quit it and try again." >&2; exit 1
        fi
    fi
done < <(pgrep -x ScreenText || true)

# Configure only this fork's preferences; upstream TRex has a different suite.
for key in LLMEnabled LLMEnableOCR FreezeScreenDuringSelection; do
    defaults write "$PREFS" "$key" -bool true
done
for key in NeedsOnboarding LLMFallbackToBuiltIn LLMEnablePostProcessing CaptureHistoryEnabled TableDetectionEnabled IgnoreLineBreaks AutomaticLanguageDetection TesseractEnabled; do
    defaults write "$PREFS" "$key" -bool false
done
defaults write "$PREFS" LLMOCRProvider -string Custom
defaults write "$PREFS" LLMOCRCustomEndpoint -string http://127.0.0.1:18871/v1
defaults write "$PREFS" LLMOCRModel -string "$MODEL"
defaults write "$PREFS" LLMOCRPrompt -string 'OCR:'
defaults write "$PREFS" LLMOCRAPIKey -string ''

if [[ -f "$PID_FILE" ]]; then
    SERVER_PID="$(cat "$PID_FILE")"
    SERVER_COMMAND="$(ps -p "$SERVER_PID" -o command= 2>/dev/null || true)"
else
    SERVER_COMMAND=""
fi
if [[ "$SERVER_COMMAND" != *"$SERVER_PATH"* ]]; then
    if curl --silent --fail http://127.0.0.1:18871/health >/dev/null; then
        echo "Port 18871 is already in use. Stop the other service first." >&2; exit 1
    fi
    "$PROJECT_DIR/.venv/bin/python" - "$PROJECT_DIR" "$MODEL" <<'PY'
import os
import subprocess
import sys
from pathlib import Path
root, model = Path(sys.argv[1]), sys.argv[2]
environment = dict(os.environ, HF_HUB_OFFLINE="1", HF_HOME=str(root / ".local/huggingface"))
with (root / ".local/server.log").open("w") as log:
    process = subprocess.Popen([str(root / ".venv/bin/python"), str(root / "Tools/local_ocr/server.py"),
        "--model", model], stdin=subprocess.DEVNULL, stdout=log, stderr=log,
        env=environment, start_new_session=True)
(root / ".local/server.pid").write_text(str(process.pid))
PY
fi
for attempt in {1..30}; do
    if curl --silent --fail http://127.0.0.1:18871/health >/dev/null; then
        open "$APP_PATH"
        echo "ScreenText is running. Press Command-Shift-2, adjust the rectangle, then choose Copy Text."
        exit 0
    fi
    sleep 1
done
echo "The local model did not start. See .local/server.log." >&2
exit 1
