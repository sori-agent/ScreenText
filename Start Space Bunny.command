#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$PROJECT_DIR/.venv/bin/python" "$PROJECT_DIR/Tools/local_ocr/space_bunny.py"
