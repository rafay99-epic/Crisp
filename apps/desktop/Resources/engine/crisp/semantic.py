"""Semantic similarity for retake detection, via the bundled `crisp-embed` helper.

Word-matching can find a *repeated* run of words; it can't tell a genuine redo (the
corrected take means the same thing as the flubbed one) from intentional parallel
structure ("at the startup level, at the enterprise level" — same shape, different
meaning). That's a meaning judgment, so the engine shells out to `crisp-embed`, a
tiny Swift tool that runs Apple's on-device NaturalLanguage sentence embeddings and
returns a cosine similarity per phrase pair. It's resolved from `CRISP_EMBED` (set by
the app to the bundled binary) exactly like ffmpeg/whisper/crisp-filler.

Everything here degrades gracefully: no `CRISP_EMBED`, an old macOS without the
embedding asset, or any subprocess error → `make_judge` returns None and retake
detection falls back to word-matching + the pause anchor (its prior behaviour). The
helper is never required; it only ever *adds* precision.
"""

import json
import math
import os
import subprocess
from pathlib import Path

# A pair whose two sides are identical — the probe that confirms the helper works and
# the embedding model is loaded before we trust it during detection.
_PROBE = ["the quick brown fox", "the quick brown fox"]

# The probe may pay the model's first cold load, so it gets a generous timeout. Each
# per-candidate judge call is bounded much tighter: an embedding is sub-second, so a
# short cap means a hung crisp-embed degrades fast instead of stalling detection for
# 30s × every candidate.
_PROBE_TIMEOUT = 30
_JUDGE_TIMEOUT = 8


def _embed_bin():
    """Absolute path to `crisp-embed` from CRISP_EMBED, or None. (Unlike ffmpeg there
    is no PATH fallback — the helper only ships inside the app.)"""
    p = os.environ.get("CRISP_EMBED")
    return p if p and Path(p).exists() else None


def _run(binp, pairs, timeout=30):
    """Send `[[a, b], …]` to the helper and return its list of cosine similarities.

    Raises on a non-zero exit or unparseable output so callers can fall back."""
    payload = json.dumps({"pairs": pairs})
    res = subprocess.run([binp], input=payload, capture_output=True, text=True,
                         timeout=timeout)
    if res.returncode != 0:
        raise RuntimeError((res.stderr or "").strip()[-300:] or f"exit {res.returncode}")
    raw = json.loads(res.stdout).get("similarities", [])
    if len(raw) != len(pairs):
        raise RuntimeError(f"expected {len(pairs)} similarities, got {len(raw)}")
    # Validate every value is a finite number here — a stray string/null/NaN would
    # otherwise reach detect_retakes and crash the clean when it formats/compares the
    # score. Raising instead lets make_judge fall back to None (gate disabled).
    sims = []
    for value in raw:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise RuntimeError(f"helper returned a non-finite similarity: {value!r}")
        sims.append(float(value))
    return sims


def make_judge(logger=None):
    """A `judge(flubbed, corrected) -> float | None` for `detect_retakes`, or None
    when the helper is unavailable. Probed once up front so detection doesn't pay for
    a broken helper on every candidate.

    The returned judge scores ONE pair per call (candidate counts are small). A
    per-call error returns None for that candidate — detection then treats it
    conservatively (keeps the pause anchor for that one), never crashing the clean."""
    binp = _embed_bin()
    if not binp:
        if logger is not None:
            logger.debug("retake semantic gate: CRISP_EMBED unset — gate disabled "
                         "(word-matching + pause anchor only)")
        return None
    try:
        sim = _run(binp, [_PROBE], timeout=_PROBE_TIMEOUT)[0]
    except Exception as e:                                   # noqa: BLE001 — log + disable
        if logger is not None:
            logger.debug(f"retake semantic gate: probe failed ({e}) — gate disabled")
        return None
    if logger is not None:
        logger.debug(f"retake semantic gate: ready via {binp} (probe sim={sim:.3f})")

    def judge(flubbed, corrected):
        if not flubbed or not corrected:
            return None
        try:
            return _run(binp, [[flubbed, corrected]], timeout=_JUDGE_TIMEOUT)[0]
        except Exception as e:                              # noqa: BLE001 — log + skip
            if logger is not None:
                logger.debug(f"retake semantic judge error ({e}) — skipping this pair")
            return None

    return judge
