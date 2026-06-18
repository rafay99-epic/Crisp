"""Build a compact waveform summary for the UI: a few dozen peak buckets over the
original audio, plus a flag per bucket for whether that slice was cut. The desktop
app renders this so the user *sees* what Crisp removed.

Reuses the analysis WAV the pipeline already extracted (mono 16 kHz PCM), so it
costs no extra decode. Pure stdlib; non-essential, so any failure yields an empty
summary rather than breaking the clean.
"""

import wave
from array import array
from pathlib import Path

# Cap samples scanned per bucket so a long recording stays fast (peaks over a
# strided scan look identical at UI resolution).
_MAX_SCAN_PER_BUCKET = 300


def _peaks_from_samples(samples, buckets):
    """Normalized (0..1) peak amplitude for each of `buckets` equal slices."""
    n = len(samples)
    if n == 0 or buckets <= 0:
        return []
    peaks = []
    for i in range(buckets):
        lo = (i * n) // buckets
        hi = max(lo + 1, ((i + 1) * n) // buckets)
        step = max(1, (hi - lo) // _MAX_SCAN_PER_BUCKET)
        peak = 0
        j = lo
        while j < hi:
            a = samples[j]
            a = -a if a < 0 else a
            if a > peak:
                peak = a
            j += step
        peaks.append(round(peak / 32768.0, 4))
    return peaks


def _removed_flags(buckets, duration, keep_segments):
    """True for each bucket whose center time falls outside every kept segment —
    i.e. the slices Crisp cut out."""
    if buckets <= 0 or duration <= 0:
        return []
    flags = []
    for i in range(buckets):
        t = (i + 0.5) * duration / buckets
        kept = any(s <= t <= e for s, e in keep_segments)
        flags.append(not kept)
    return flags


def waveform_summary(wav_path, duration, keep_segments, buckets=120):
    """Read the analysis WAV and return {"peaks": [...], "removed": [bool, ...]}.
    Returns empties on any problem — the waveform is a nicety, never load-bearing."""
    try:
        with wave.open(str(Path(wav_path)), "rb") as w:
            if w.getsampwidth() != 2:
                return {"peaks": [], "removed": []}
            samples = array("h")
            samples.frombytes(w.readframes(w.getnframes()))
        return {
            "peaks": _peaks_from_samples(samples, buckets),
            "removed": _removed_flags(buckets, duration, keep_segments),
        }
    except Exception:
        # The waveform is a nicety; whatever goes wrong (unreadable WAV, an odd
        # format, even MemoryError on an hours-long file) must never fail the clean.
        return {"peaks": [], "removed": []}
