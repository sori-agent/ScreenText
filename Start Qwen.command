#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$PROJECT_DIR/.venv/bin/python" "$PROJECT_DIR/Tools/local_ocr/openrouter_ocr.py" qwen/qwen3.7-flash
