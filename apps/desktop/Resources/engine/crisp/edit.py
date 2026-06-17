"""Editing: back up the original, decide what to keep, and render the result.

This is the cutting half of the engine — it acts on what `detect` found.
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .config import MIN_KEEP
from .errors import CleanError
from .text import is_filler
from .tools import ffmpeg_bin


def make_backup(src: Path, on_log, backup_dir: Path | None = None) -> Path:
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
    shutil.copy2(src, dest)
    return dest


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


def render(src, keep, out_path, on_log, on_progress, video_opts, audio_opts, mux_opts=()):
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
        proc = subprocess.Popen(
            [ffmpeg_bin(), "-y", "-i", str(src),
             "-filter_complex_script", graph_path,
             "-map", "[outv]", "-map", "[outa]",
             *video_opts, *audio_opts, *mux_opts,
             "-progress", "pipe:1", "-nostats", str(out_path)],
            stdout=subprocess.PIPE, stderr=err_file, text=True,
        )
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
        if proc.returncode != 0 or not out_path.exists():
            err_file.seek(0)
            raise CleanError(f"Rendering failed.\n{err_file.read()[-1500:]}")
    finally:
        os.unlink(graph_path)
        err_file.close()
        os.unlink(err_file.name)
