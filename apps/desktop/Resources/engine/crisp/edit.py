"""Editing: back up the original, decide what to keep, and render the result.

This is the cutting half of the engine — it acts on what `detect` found.
"""

import json
import math
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .config import FILLER_MIN_SOLO, FILLER_PAUSE_PAD, MIN_KEEP
from .enginelog import EngineLogger
from .errors import CleanError
from .text import is_filler
from .tools import ffmpeg_bin


def gate_fillers_by_silence(words, silences, min_solo=FILLER_MIN_SOLO, pad=FILLER_PAUSE_PAD):
    """Keep only the on-device classifier's fillers worth cutting.

    A filler is removable if it's a clearly long, deliberate hesitation OR sits right
    at a pause boundary (silence just before or after it). Brief fillers embedded in
    continuous speech are dropped — cutting those mid-sentence removes natural delivery
    and makes a rough jump-cut. Whisper fillers don't need this (it only flags sounds
    it actually transcribes as "um"/"uh").
    """
    if not words or not silences:
        return words
    kept = []
    for w in words:
        long_enough = (w["end"] - w["start"]) >= min_solo
        at_pause = any(abs(se - w["start"]) <= pad or abs(ss - w["end"]) <= pad
                       for ss, se in silences)
        if long_enough or at_pause:
            kept.append(w)
    return kept


def make_backup(src: Path, on_log, backup_dir: Path | None = None, logger=None) -> Path:
    logger = logger or EngineLogger(None)
    # Default to an `_originals` folder beside the source (the bare-CLI behavior);
    # the desktop app passes an explicit dir (a dated folder under its data home).
    backup_dir = Path(backup_dir) if backup_dir else src.parent / "_originals"
    backup_dir.mkdir(parents=True, exist_ok=True)
    dest = backup_dir / src.name
    if dest.exists():
        i = 1
        while True:
            cand = backup_dir / f"{src.stem}_{i}{src.suffix}"
            if not cand.exists():
                dest = cand
                break
            i += 1
    on_log(f"Backing up original to: {dest}")
    logger.debug(f"backup {src} -> {dest}")
    shutil.copy2(src, dest)
    return dest


# Extended attribute recording which source produced a cleaned file, so a shared
# output folder can tell "re-clean of the same video" (overwrite) apart from "a
# different video that happens to share a name" (write a _1 copy). The Swift
# watcher reads the same key (see WatchController). Keep this string in sync.
#
# `os.getxattr`/`os.setxattr` are Linux-only, so on macOS we reach the libc
# functions through ctypes. If that ever fails to load, the helpers degrade to
# "no tag": `unique_output_path` then just dedups, so a cleaned file is never lost
# (re-cleans get a _1 copy instead of overwriting — the safe way to fail).
SOURCE_XATTR = "user.crisp.source"

try:
    import ctypes

    _libc = ctypes.CDLL(None, use_errno=True)
    _libc.getxattr.restype = ctypes.c_ssize_t
    _libc.getxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                               ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    _libc.setxattr.restype = ctypes.c_int
    _libc.setxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                               ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
except (OSError, AttributeError):  # pragma: no cover - platform without these symbols
    _libc = None


def _output_owner(path: Path):
    """The source path (bytes) recorded on `path`, or None if untagged / xattrs
    aren't available."""
    if _libc is None:
        return None
    name = SOURCE_XATTR.encode()
    p = os.fsencode(path)
    size = _libc.getxattr(p, name, None, 0, 0, 0)
    if size < 0:
        return None
    buf = ctypes.create_string_buffer(size)
    if _libc.getxattr(p, name, buf, size, 0, 0) < 0:
        return None
    return buf.raw[:size]


def unique_output_path(out_path: Path, src: Path) -> Path:
    """Choose a final output path that never overwrites a *different* source's
    cleaned file. Re-cleaning the same source reuses (overwrites) its own previous
    output; a different source mapping to the same name gets `_1`, `_2`, …. Where
    xattrs aren't supported, this falls back to plain dedup — so a cleaned file is
    never silently lost."""
    marker = os.fsencode(str(src))
    candidate, i = out_path, 0
    while candidate.exists() and _output_owner(candidate) != marker:
        i += 1
        candidate = out_path.with_name(f"{out_path.stem}_{i}{out_path.suffix}")
    return candidate


def tag_output_source(out_path: Path, src: Path) -> None:
    """Record which source produced this cleaned file (best-effort)."""
    if _libc is None:
        return
    value = os.fsencode(str(src))
    _libc.setxattr(os.fsencode(out_path), SOURCE_XATTR.encode(), value, len(value), 0, 0)


def build_keep_segments(words, silences, duration, keep_pause, min_keep=MIN_KEEP):
    """Return (keep, stats): list of (start, end) seconds to KEEP, plus counts."""
    remove = []
    stats = {"fillers": 0, "pauses": 0}

    for s, e in silences:                       # long pauses (trim middle of silence)
        inner_s, inner_e = s + keep_pause, e - keep_pause
        if inner_e - inner_s > 0.01:
            remove.append((inner_s, inner_e))
            stats["pauses"] += 1

    for w in words:                             # filler words (exact span)
        if is_filler(w["text"]):
            remove.append((w["start"], w["end"]))
            stats["fillers"] += 1

    cleaned = []
    for s, e in remove:
        s, e = max(0.0, s), min(duration, e)
        if e - s > 0.01:
            cleaned.append((s, e))
    cleaned.sort()
    merged = []
    for s, e in cleaned:
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))

    keep, cursor = [], 0.0
    for s, e in merged:
        if s - cursor >= min_keep:
            keep.append((cursor, s))
        cursor = max(cursor, e)
    if duration - cursor >= min_keep:
        keep.append((cursor, duration))
    return keep, stats


def load_keep_segments(path, duration):
    """Load an explicit list of (start, end) seconds to KEEP from a JSON file
    (`{"keep": [[start, end], ...]}`) — as written by the desktop app's review
    timeline, where the user toggled individual cuts by hand. Validates, clamps to
    `[0, duration]`, sorts, and merges touching/overlapping segments so the result
    is exactly the non-overlapping keep list `render()` expects. Raises CleanError on
    a missing/unreadable/malformed file or an empty result (never silently render the
    whole video when the edit list is broken)."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise CleanError(f"Couldn't read the reviewed cut list.\n{e}")

    raw = data.get("keep") if isinstance(data, dict) else None
    if not isinstance(raw, list):
        raise CleanError("The reviewed cut list is malformed (missing a 'keep' array).")

    segs = []
    for pair in raw:
        # Skip anything that isn't a 2-element [start, end] (incl. dict-shaped entries,
        # which would raise KeyError) rather than failing the whole list.
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            continue
        try:
            s, e = float(pair[0]), float(pair[1])
        except (TypeError, ValueError):
            continue
        if not (math.isfinite(s) and math.isfinite(e)):
            continue                      # reject nan/inf — they'd clamp to bogus ranges
        s, e = max(0.0, s), min(duration, e)
        if e - s > 0.01:
            segs.append((s, e))

    segs.sort()
    merged = []
    for s, e in segs:
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))

    if not merged:
        raise CleanError("The reviewed cut list had no usable segments to keep.")
    return merged


def render(src, keep, out_path, on_log, on_progress, video_opts, audio_opts, mux_opts=(), logger=None):
    logger = logger or EngineLogger(None)
    on_log(f"Rendering cleaned video ({len(keep)} segments kept)...")
    total = sum(e - s for s, e in keep) or 1.0

    lines, labels = [], []
    for i, (s, e) in enumerate(keep):
        lines.append(f"[0:v]trim=start={s:.3f}:end={e:.3f},setpts=PTS-STARTPTS[v{i}];")
        lines.append(f"[0:a]atrim=start={s:.3f}:end={e:.3f},asetpts=PTS-STARTPTS[a{i}];")
        labels.append(f"[v{i}][a{i}]")
    lines.append("".join(labels) + f"concat=n={len(keep)}:v=1:a=1[outv][outa]")

    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as tf:
        tf.write("\n".join(lines))
        graph_path = tf.name
    err_file = tempfile.NamedTemporaryFile("w+", suffix=".log", delete=False)

    try:
        cmd = [ffmpeg_bin(), "-y", "-i", str(src),
               "-filter_complex_script", graph_path,
               "-map", "[outv]", "-map", "[outa]",
               *video_opts, *audio_opts, *mux_opts,
               "-progress", "pipe:1", "-nostats", str(out_path)]
        logger.command("ffmpeg render", cmd)
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=err_file, text=True)
        for line in proc.stdout:
            line = line.strip()
            if line.startswith("out_time_us=") or line.startswith("out_time_ms="):
                try:
                    val = int(line.split("=")[1])
                    secs = val / 1_000_000.0  # both keys are microseconds in practice
                    frac = max(0.0, min(1.0, secs / total))
                    on_progress(frac, f"Rendering… {int(frac * 100)}%")
                except (IndexError, ValueError):
                    pass
        proc.wait()
        err_file.seek(0)
        err_text = err_file.read()
        logger.tool_result("ffmpeg render", proc.returncode,
                           err_text if (proc.returncode != 0 or not out_path.exists()) else "")
        if proc.returncode != 0 or not out_path.exists():
            raise CleanError(f"Rendering failed.\n{err_text[-1500:]}")
    finally:
        os.unlink(graph_path)
        err_file.close()
        os.unlink(err_file.name)
