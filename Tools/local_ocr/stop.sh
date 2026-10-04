#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PID_FILE="$PROJECT_DIR/.local/server.pid"
SERVER_PATH="$PROJECT_DIR/Tools/local_ocr/server.py"
if [[ -f "$PID_FILE" ]]; then
    SERVER_PID="$(cat "$PID_FILE")"
    SERVER_COMMAND="$(ps -p "$SERVER_PID" -o command= 2>/dev/null || true)"
    if [[ "$SERVER_COMMAND" == *"$SERVER_PATH"* ]]; then
        kill "$SERVER_PID"
        for attempt in {1..30}; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
            sleep 1
        done
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "OCR is still shutting down. Try stopping again when the request finishes." >&2
            exit 1
        fi
    fi
    rm "$PID_FILE"
fi
echo "Local OCR server stopped. Quit ScreenText from its menu bar menu."
