#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$PROJECT_DIR/.local/DerivedData/Build/Products/Debug/ScreenText.app"
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
for key in LLMEnabled LLMEnableOCR; do
    defaults write "$PREFS" "$key" -bool true
done
for key in NeedsOnboarding FreezeScreenDuringSelection LLMFallbackToBuiltIn LLMEnablePostProcessing CaptureHistoryEnabled TableDetectionEnabled IgnoreLineBreaks AutomaticLanguageDetection TesseractEnabled; do
    defaults write "$PREFS" "$key" -bool false
done
defaults write "$PREFS" LLMOCRProvider -string Custom
defaults write "$PREFS" LLMOCRCustomEndpoint -string http://127.0.0.1:18871/v1
defaults write "$PREFS" LLMOCRModel -string "$MODEL"
defaults write "$PREFS" LLMOCRPrompt -string 'OCR:'
defaults write "$PREFS" LLMOCRAPIKey -string ''
defaults write "$PREFS" LocalOCRProjectDirectory -string "$PROJECT_DIR"

# The app owns the server process; the launcher only configures and opens it.
open "$APP_PATH"
for attempt in {1..30}; do
    if curl --silent --fail http://127.0.0.1:18871/health >/dev/null; then
        echo "ScreenText is running. Press Command-Shift-2, drag a rectangle, and release to copy text."
        exit 0
    fi
    sleep 1
done
echo "The local model did not start. See .local/server.log." >&2
exit 1
