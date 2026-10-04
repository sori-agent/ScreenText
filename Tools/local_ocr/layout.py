"""Use text geometry to read horizontal regions without a full-page model pass."""

import math
import io
import json
import subprocess
from pathlib import Path
from typing import Callable
from PIL import Image

Rect = tuple[float, float, float, float]


def detect_regions(image: Image.Image, executable: Path) -> list[Rect]:
    """Send PNG bytes through stdin and receive only text bounding rectangles."""
    encoded = io.BytesIO()
    image.save(encoded, format="PNG")
    result = subprocess.run([str(executable)], input=encoded.getvalue(),
                            capture_output=True, check=True, timeout=30)
    return [(r["x"], r["y"], r["width"], r["height"]) for r in json.loads(result.stdout)]


def recognize_horizontal(image: Image.Image, regions: list[Rect], read: Callable[[Image.Image], str]) -> str:
    """Read left to right within each row, keeping small annotations above it."""
    horizontal = [r for r in regions if r[2] >= r[3] * 1.2]
    # A narrow single character can still belong to a horizontal row or ruby.
    for region in regions:
        x, y, w, h = region
        if region in horizontal:
            continue
        if any(
            (abs(y + h / 2 - py - ph / 2) < min(h, ph) / 2 and min(abs(x - px - pw), abs(px - x - w)) < ph * 2)
            or (h <= ph * 0.75 and 0 <= py - y - h <= ph * 2 and x < px + pw and x + w > px)
            for px, py, pw, ph in horizontal
        ):
            horizontal.append(region)
    rows: list[list[Rect]] = []
    for region in sorted(horizontal, key=lambda r: (r[1], r[0])):
        for row in rows:
            reference = row[0]
            if abs(region[1] + region[3] / 2 - reference[1] - reference[3] / 2) <= min(region[3], reference[3]) * 0.5:
                row.append(region)
                break
        else:
            rows.append([region])
    output = []
    left_margin = min((r[0] for r in horizontal), default=0)
    for row in rows:
        fragments = []
        previous = None
        for x, y, w, h in sorted(row, key=lambda r: r[0]):
            padding = max(2, h * 0.12)
            box = (max(0, math.floor(x - padding)), max(0, math.floor(y - padding)),
                   min(image.width, math.ceil(x + w + padding)), min(image.height, math.ceil(y + h + padding)))
            with image.crop(box) as crop:
                text = read(crop).strip()
            if not text:
                continue
            if previous is not None:
                gap = x - previous[0] - previous[2]
                if gap >= min(h, previous[3]) * 0.4:
                    fragments.append(" ")
            fragments.append(text)
            previous = (x, y, w, h)
        if fragments:
            # Approximate the ruby offset using spaces in the plain-text clipboard.
            row_height = max(r[3] for r in row)
            indent = min(80, round((min(r[0] for r in row) - left_margin) / max(1, row_height / 2)))
            output.append(" " * indent + "".join(fragments))
    return "\n".join(output)
