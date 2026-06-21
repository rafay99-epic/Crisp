"""Label format + helpers.

A label file is JSON next to the audio: a list of filler intervals in seconds.

    {"fillers": [[1.20, 1.46], [8.03, 8.31]]}

Everything outside those intervals is treated as non-filler. Silence is *not*
labeled here — the engine already removes pauses with ffmpeg silencedetect, so
this model only has to learn filler-vs-speech.
"""
from __future__ import annotations

import json
import math
from pathlib import Path


def load_intervals(path) -> list:
    """Read a *.fillers.json file → list of (start, end) tuples in seconds.

    Fails fast on malformed pairs (non-finite, or end <= start) so a bad label file
    can't silently corrupt training/eval targets.
    """
    data = json.loads(Path(path).read_text())
    intervals = []
    for a, b in data.get("fillers", []):
        a, b = float(a), float(b)
        if not (math.isfinite(a) and math.isfinite(b)) or b <= a:
            raise ValueError(f"{path}: invalid filler interval [{a}, {b}] (need finite, end > start)")
        intervals.append((a, b))
    return intervals


def save_intervals(path, intervals) -> None:
    payload = {"fillers": [[round(float(a), 3), round(float(b), 3)] for a, b in intervals]}
    Path(path).write_text(json.dumps(payload, indent=2))


def label_for_time(t: float, intervals) -> int:
    """1 if time t (seconds) falls inside any filler interval, else 0."""
    for a, b in intervals:
        if a <= t < b:
            return 1
    return 0
