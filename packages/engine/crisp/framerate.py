"""Frame-rate policy: decide whether a source is variable-frame-rate (VFR) and
what constant rate to normalize it to.

Screen recorders (OBS, ScreenCaptureKit, QuickTime) emit a new frame only when
the picture changes, so their *average* frame rate falls below the nominal *base*
rate — the file is VFR. Crisp's trim→setpts→concat render assumes steady timing,
so on a VFR source the cut video can drift out of sync with the (constant-rate)
audio over a long timeline. Normalizing the render to a constant frame rate fixes
that.

These are pure functions (no ffmpeg) so the policy is unit-testable; the ffprobe
call that feeds them lives in `tools.probe_video_fps`.
"""

# A source counts as VFR when its average rate sits meaningfully below its base
# (r) rate. A true CFR file has avg == r; the tolerance absorbs container rounding
# (e.g. a base reported as 30/1 with an average of 30000/1001).
VFR_REL_TOL = 0.005          # 0.5%
# Frame rates outside this range are treated as implausible metadata (some
# containers report a huge timebase-derived base rate); we don't normalize to them.
MAX_PLAUSIBLE_FPS = 240.0


def parse_fraction(text):
    """ffprobe rate strings are ``num/den`` (e.g. ``30000/1001``); return a float,
    or None for ``0/0`` / ``N/A`` / empty / malformed input."""
    if not text:
        return None
    text = text.strip()
    if not text or text.upper() == "N/A":
        return None
    try:
        if "/" in text:
            num, den = text.split("/", 1)
            den = float(den)
            return float(num) / den if den else None
        return float(text)
    except (ValueError, ZeroDivisionError):
        return None


def _plausible(fps):
    return fps is not None and 0 < fps <= MAX_PLAUSIBLE_FPS


def is_vfr(r_fps, avg_fps, tol=VFR_REL_TOL):
    """True when the average rate falls below the base rate by more than `tol`
    (relative). Unknown/zero rates → not VFR (we never normalize what we can't read,
    so a good CFR file is left untouched)."""
    if not r_fps or r_fps <= 0 or not avg_fps or avg_fps <= 0:
        return False
    return (r_fps - avg_fps) / r_fps > tol


def _fmt(fps):
    """Format a float fps as a clean ffmpeg ``-r`` value (``30`` not ``30.0``)."""
    return f"{fps:g}"


def resolve_target_fps(mode, requested_fps, r_text, avg_text):
    """The ffmpeg ``-r`` value (a string) to force constant frame rate, or None to
    leave the source's timing alone.

    mode:
      ``passthrough`` — never change the rate (the pre-VFR-feature behavior).
      ``constant``    — always force ``requested_fps``.
      ``auto``        — normalize ONLY a VFR source, to its nominal base rate (a
                        clean CFR value editors expect), or to ``requested_fps`` if
                        the caller supplied one; falls back to the measured average
                        when the base rate looks implausible. A CFR source returns
                        None (untouched).
    """
    if mode == "passthrough":
        return None
    if mode == "constant":
        return _fmt(requested_fps) if _plausible(requested_fps) else None

    # auto
    r_fps = parse_fraction(r_text)
    avg_fps = parse_fraction(avg_text)
    if not is_vfr(r_fps, avg_fps):
        return None
    if _plausible(requested_fps):
        return _fmt(requested_fps)
    if _plausible(r_fps):
        return (r_text or "").strip()        # exact base fraction (e.g. 30000/1001)
    if _plausible(avg_fps):
        return (avg_text or "").strip()
    return None
