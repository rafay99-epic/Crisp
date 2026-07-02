"""Editing: back up the original, decide what to keep, and render the result.

This is the cutting half of the engine — it acts on what `detect` found.
"""

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .config import (DEFAULT_PAUSE_MODE, DEFAULT_SNAP_MS, DEFAULT_TIGHT_PAUSE,
                     FILLER_MIN_SOLO, FILLER_PAUSE_PAD, MIN_KEEP)
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

# The prototypes below are the 6-argument BSD/macOS signatures. Only load them on
# macOS: Windows has no CDLL(None) at all, and Linux's get/setxattr take 4/5 args —
# calling them through a mismatched prototype only works by ABI accident. Everywhere
# but macOS we degrade to the dedup fallback (re-cleans get a _1 copy — the safe
# way to fail).
_libc = None
if sys.platform == "darwin":
    try:
        import ctypes

        _libc = ctypes.CDLL(None, use_errno=True)
        _libc.getxattr.restype = ctypes.c_ssize_t
        _libc.getxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
        _libc.setxattr.restype = ctypes.c_int
        _libc.setxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.c_uint32, ctypes.c_int]
    except (OSError, AttributeError):  # pragma: no cover - libc without these symbols
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


def build_keep_segments(words, silences, duration, keep_pause, min_keep=MIN_KEEP, retakes=None,
                        pause_mode=DEFAULT_PAUSE_MODE, tight_pause=DEFAULT_TIGHT_PAUSE):
    """Return (keep, stats): list of (start, end) seconds to KEEP, plus counts.

    `retakes` is an optional list of (start, end) spans for flubbed takes the speaker
    immediately repeated (see crisp.retake) — removed wholesale alongside pauses and
    fillers.
    `pause_mode` — "remove" (default) cuts each detected pause entirely; "tighten"
    keeps `tight_pause` extra seconds of silence at the pause start (on top of
    `keep_pause`) so the pacing stays natural instead of machine-gunned. Any other
    value behaves as "remove". A pause already shorter than the kept gap is left
    untouched (and not counted)."""
    remove = []
    stats = {"fillers": 0, "pauses": 0, "retakes": 0}

    for s, e in silences:                       # long pauses (trim middle of silence)
        inner_s, inner_e = s + keep_pause, e - keep_pause
        if pause_mode == "tighten":
            inner_s += max(0.0, tight_pause)  # a negative gap must never cut into speech
        if inner_e - inner_s > 0.01:
            remove.append((inner_s, inner_e))
            stats["pauses"] += 1

    for w in words:                             # filler words (exact span)
        if is_filler(w["text"]):
            remove.append((w["start"], w["end"]))
            stats["fillers"] += 1

    for s, e in (retakes or []):                # repeated takes (cut the first attempt)
        if e - s > 0.01:
            remove.append((s, e))
            stats["retakes"] += 1

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


def _nearest_zero_crossing(samples, center, max_off):
    """Index nearest `center` (searching ±max_off) where the signal crosses zero;
    returns `center` itself when there's no crossing in range. Pure arithmetic on a
    sequence of signed ints, so it's unit-testable without any audio decode."""
    n = len(samples)
    if n == 0:
        return center
    center = max(0, min(n - 1, center))
    for off in range(max_off + 1):
        for idx in (center + off, center - off):   # expand outward, prefer the later side on ties
            if 1 <= idx < n and (samples[idx - 1] <= 0 <= samples[idx]
                                 or samples[idx - 1] >= 0 >= samples[idx]):
                return idx
    return center


def snap_keep_to_zero_crossings(keep, wav_path, window_s=None, logger=None):
    """Nudge each interior cut boundary in `keep` to the nearest audio zero-crossing
    within ±`window_s` (Phase 3). Cuts placed mid-waveform are the click source; a
    boundary that lands where the signal is already ~0 splices silently. Reads only a
    small window around each boundary from the analysis WAV (stdlib `wave`, 16-bit mono
    as `extract_audio` produces). Best-effort: any read problem returns `keep` unchanged
    (the Phase-1 fade still removes the click), and clip head/tail are left alone.

    `window_s` is resolved from `DEFAULT_SNAP_MS` at call time (not bound at import),
    so a future per-model override of the default is honored."""
    logger = logger or EngineLogger(None)
    if window_s is None:
        window_s = DEFAULT_SNAP_MS / 1000.0
    if window_s <= 0 or len(keep) < 2:
        return keep
    import array
    import wave
    try:
        with wave.open(str(wav_path), "rb") as w:
            if w.getsampwidth() != 2 or w.getnchannels() != 1:
                return keep
            sr, nframes = w.getframerate(), w.getnframes()
            win = max(1, int(window_s * sr))
            audio_dur = nframes / sr if sr else 0.0

            def snap(t):
                if t <= window_s or t >= audio_dur - window_s:
                    return t                       # don't trim the clip's own head/tail
                center = int(round(t * sr))
                lo, hi = max(0, center - win), min(nframes, center + win + 1)
                if hi - lo < 2:
                    return t
                w.setpos(lo)
                buf = array.array("h")
                buf.frombytes(w.readframes(hi - lo))
                return (lo + _nearest_zero_crossing(buf, center - lo, win)) / sr

            snapped = [(snap(s), snap(e)) for s, e in keep]
    except (OSError, wave.Error, ValueError, EOFError) as e:
        logger.debug(f"zero-cross snap skipped: {e}")
        return keep

    # Re-validate. Snapping is only a refinement, so it must NEVER lose content.
    # Two guards make that airtight: (a) a snapped END can't move past the NEXT
    # segment's original start — so a forward nudge can't eat into the next kept
    # segment, which keeps `prev_end` <= the next segment's original start; (b) if a
    # nudge still shrank a segment below the epsilon, fall back to its ORIGINAL span.
    # Because of (a), that fallback's `max(orig_s, prev_end)` is always `orig_s`, so
    # the original segment survives whole.
    out, prev_end = [], 0.0
    for i, ((orig_s, orig_e), (snap_s, snap_e)) in enumerate(zip(keep, snapped, strict=True)):
        next_orig_s = keep[i + 1][0] if i + 1 < len(keep) else math.inf
        cs = max(snap_s, prev_end)
        ce = min(snap_e, next_orig_s)
        if ce - cs <= 0.01:                              # snap degraded it → keep original
            logger.notice(f"zero-cross snap shrank a segment at {orig_s:.3f}s below 0.01s; "
                          f"kept its original boundaries (no content dropped)")
            cs, ce = max(orig_s, prev_end), orig_e
        if ce - cs > 0.01:
            out.append((cs, ce))
            prev_end = ce
    return out or keep


def _clamped_crossfade(durs, crossfade):
    """The crossfade actually applied: clamped to half the shortest segment so a
    brief sliver can't break the dissolve (0 = hard cuts). The single source of truth
    shared by build_filter_graph (the graph), render (progress), and the pipeline
    (duration accounting)."""
    return min(crossfade, min(durs) * 0.5) if (crossfade > 0 and durs) else 0.0


def output_duration(keep, crossfade=0.0):
    """Rendered length of `keep`. With a real crossfade each of the (n-1) joins
    overlaps by `c`, so the output is shorter than the raw sum of kept spans by
    (n-1)*c — mirrors exactly what build_filter_graph emits, so progress and the
    reported new/saved seconds match the actual file."""
    durs = [e - s for s, e in keep]
    total = sum(durs)
    c = _clamped_crossfade(durs, crossfade)
    if len(keep) >= 2 and c > 0.001:
        total -= (len(keep) - 1) * c
    return total


def build_filter_graph(keep, fade=0.0, crossfade=0.0):
    """The `-filter_complex_script` lines that trim `keep` (list of (start, end) secs)
    out of input 0 and join the pieces into `[outv][outa]`. Factored out of `render`
    so the cut-smoothing graph is pure and unit-testable (no ffmpeg needed).

    fade>0       — a short audio fade in/out on every segment so hard joins don't click.
    crossfade>0  — dissolve consecutive segments (matched video `xfade` + audio
                   `acrossfade`, same duration → stays in A/V sync) instead of hard
                   cuts; overrides `fade`. Clamped to the shortest segment so a brief
                   kept sliver can't break the dissolve.
    """
    if not keep:
        raise ValueError("build_filter_graph: keep must not be empty")
    n = len(keep)
    durs = [e - s for s, e in keep]
    lines = []
    # Microsecond precision (.6f): millisecond rounding would re-round the
    # zero-crossing snap away (8 samples at 16 kHz) and let cut positions drift.
    for i, (s, e) in enumerate(keep):
        lines.append(f"[0:v]trim=start={s:.6f}:end={e:.6f},setpts=PTS-STARTPTS[v{i}];")
        a = f"[0:a]atrim=start={s:.6f}:end={e:.6f},asetpts=PTS-STARTPTS"
        if crossfade <= 0 and fade > 0:
            f = min(fade, durs[i] / 2)
            a += (f",afade=t=in:st=0:d={f:.6f},afade=t=out:st={durs[i] - f:.6f}:d={f:.6f}")
        lines.append(a + f"[a{i}];")

    # Clamp the dissolve to the shortest segment; fall back to a hard concat if there's
    # nothing long enough to dissolve (or only one segment).
    c = _clamped_crossfade(durs, crossfade)
    if c <= 0.001 or n < 2:
        labels = "".join(f"[v{i}][a{i}]" for i in range(n))
        lines.append(labels + f"concat=n={n}:v=1:a=1[outv][outa]")
        return lines

    # `length` is the accumulated output timeline so far = sum(durs[:i]) - (i-1)*c
    # (each prior dissolve overlapped by `c`); the next xfade starts `c` before its end.
    prev_v, prev_a, length = "v0", "a0", durs[0]
    for i in range(1, n):
        last = i == n - 1
        ov, oa = ("outv", "outa") if last else (f"vx{i}", f"ax{i}")
        offset = length - c
        lines.append(f"[{prev_v}][v{i}]xfade=transition=fade:duration={c:.6f}:offset={offset:.6f}[{ov}];")
        lines.append(f"[{prev_a}][a{i}]acrossfade=d={c:.6f}[{oa}]" + (";" if not last else ""))
        prev_v, prev_a, length = ov, oa, length + durs[i] - c
    return lines


# ffmpeg's filter-graph scheduling cost grows superlinearly with the number of live
# filters, and the trim graph carries ~4 per kept segment — measured QUADRATIC
# wall-clock in segment count (on a 60s clip: 50 segments ≈ 1s of graph overhead,
# 600 ≈ 100s; concat trees and reduced fan-out don't help, only a smaller graph
# does). Past the threshold, render in batches of _BATCH_SIZE segments — each a
# small flat graph over an input-seeked window — and losslessly join the parts.
# Below it, the single-pass graph is cheap and stays the well-trodden default.
_BATCH_THRESHOLD = 64
_BATCH_SIZE = 32


def _should_batch(keep, crossfade, fps):
    """Route this render to the batched many-cuts path? Pure/unit-tested.

    Requires all of: enough segments to pay off the batch overhead; no crossfade
    (dissolves chain pairwise across the whole timeline, so they can't batch); and
    NO frame-rate conform active (`fps is None`). A constant-frame-rate conform
    (`-r`) is a GLOBAL dup/drop decision over the whole output timeline — running it
    independently per batch and stream-copy-joining the parts does NOT reproduce the
    single-pass frame grid (which batch owns a grid point landing on a batch seam is
    globally coupled, so frame count and placement diverge). A VFR source needing
    normalization therefore takes the correct single-pass graph, trading the batch
    speedup for a frame-exact result."""
    return (fps is None
            and len(keep) > _BATCH_THRESHOLD
            and _clamped_crossfade([e - s for s, e in keep], crossfade) <= 0.001)


def render(src, keep, out_path, on_log, on_progress, video_opts, audio_opts, mux_opts=(),
           fade=0.0, crossfade=0.0, fps=None, logger=None):
    logger = logger or EngineLogger(None)
    on_log(f"Rendering cleaned video ({len(keep)} segments kept)...")
    # Progress denominator = the actual output length (a crossfade shortens it by
    # (n-1)*c), so out_time_* reaches 100% instead of stalling under it.
    total = output_duration(keep, crossfade) or 1.0

    # `-r` on the OUTPUT conforms the cut video to a constant frame rate
    # (dup/drop frames to even spacing). Set only when normalizing a VFR source
    # (or an explicit constant); a CFR source passes None and keeps its timing.
    fps_opts = ["-r", str(fps)] if fps else []

    # Never write the final file in place: a re-clean of the same source deliberately
    # resolves to its PREVIOUS output (see unique_output_path), so ffmpeg truncating
    # `out_path` at t=0 would destroy the user's existing good file the moment a
    # render fails, runs out of disk, or is cancelled (app cancel is a SIGKILL of the
    # process group — no cleanup runs). Render to a sibling `.part` and publish with
    # os.replace() (atomic on POSIX and NTFS) only on success; the trailing container
    # extension is kept so ffmpeg still infers the right muxer. A `.part` orphaned by
    # SIGKILL is overwritten (-y) or unlinked on the next render to the same output.
    part_path = out_path.with_name(out_path.stem + ".part" + out_path.suffix)

    # Many cuts → the batched path (see _should_batch: enough segments, no
    # crossfade, and no fps conform — a per-batch `-r` doesn't match the single-pass
    # frame grid, so VFR normalization stays on the single-pass graph).
    if _should_batch(keep, crossfade, fps):
        return _render_batched(src, keep, out_path, part_path, on_log, on_progress,
                               video_opts, audio_opts, mux_opts, fade,
                               total, logger)

    lines = build_filter_graph(keep, fade=fade, crossfade=crossfade)
    with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8", delete=False) as tf:
        tf.write("\n".join(lines))
        graph_path = tf.name
    try:
        cmd = [ffmpeg_bin(), "-y", "-i", str(src),
               "-filter_complex_script", graph_path,
               "-map", "[outv]", "-map", "[outa]",
               *video_opts, *fps_opts, *audio_opts, *mux_opts,
               "-progress", "pipe:1", "-nostats", str(part_path)]
        last = {"frac": 0.0}

        def on_secs(secs):
            last["frac"] = max(0.0, min(1.0, secs / total))
            _emit_render_progress(on_progress, last["frac"])

        rc, err_text = _run_ffmpeg_progress(cmd, logger, "ffmpeg render", on_secs)
        logger.tool_result("ffmpeg render", rc,
                           err_text if (rc != 0 or not part_path.exists()) else "")
        if rc != 0 or not part_path.exists():
            err = CleanError(f"Rendering failed.\n{err_text[-1500:]}")
            # How far the render got before dying — the pipeline's encoder-fallback
            # ladder uses this to tell "encoder couldn't start" (retry in software)
            # from "died mid-render" (disk/I/O — retrying just re-burns hours).
            err.render_progress = last["frac"]
            raise err
        os.replace(part_path, out_path)
    finally:
        part_path.unlink(missing_ok=True)  # no-op on success (already replaced away)
        os.unlink(graph_path)


def _run_ffmpeg_progress(cmd, logger, name, on_secs):
    """Run an ffmpeg command that reports `-progress pipe:1`, streaming each parsed
    out_time (seconds) to `on_secs`. Returns (returncode, stderr_text). Kills ffmpeg
    instead of orphaning it if the callback raises (e.g. BrokenPipeError when the
    parent app died). Pipes and the stderr file are explicit UTF-8 — on Windows the
    default locale code page (cp1252, strict) crashes on the multibyte filenames
    ffmpeg happily echoes into stderr."""
    err_file = tempfile.NamedTemporaryFile("w+", suffix=".log", encoding="utf-8",
                                           errors="replace", delete=False)
    try:
        logger.command(name, cmd)
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=err_file, text=True,
                                encoding="utf-8", errors="replace")
        try:
            for line in proc.stdout:
                line = line.strip()
                if line.startswith("out_time_us=") or line.startswith("out_time_ms="):
                    try:
                        # both keys are microseconds in practice
                        on_secs(int(line.split("=")[1]) / 1_000_000.0)
                    except (IndexError, ValueError):
                        pass
            proc.wait()
        except BaseException:
            proc.kill()
            proc.wait()
            raise
        err_file.seek(0)
        return proc.returncode, err_file.read()
    finally:
        err_file.close()
        os.unlink(err_file.name)


# How far before a batch's first segment the input seek lands. Covers decoder
# warm-up (audio codecs need a running state to reproduce the exact samples a
# continuous decode yields; open-GOP video can reference across its seek keyframe)
# so the frames/samples at the window edge are bit-identical to a full decode.
_BATCH_SEEK_PAD = 1.0


def _batch_windows(keep, size=None):
    """Chunk `keep` into batches of `size` segments: a list of
    (seek_start, read_stop, segments) — segments stay in ABSOLUTE source
    coordinates (the batches render with `-copyts`, so trim compares the same
    absolute timestamps the single-pass graph does; rebasing would quantize to the
    container timebase and flip frames that sit exactly on a cut boundary).
    Pure, unit-tested."""
    size = size or _BATCH_SIZE
    out = []
    for i in range(0, len(keep), size):
        batch = keep[i:i + size]
        seek = max(0.0, batch[0][0] - _BATCH_SEEK_PAD)
        stop = batch[-1][1] + 0.25   # small demux margin; trim is end-exclusive
        out.append((seek, stop, list(batch)))
    return out


def _emit_render_progress(on_progress, frac):
    frac = max(0.0, min(1.0, frac))
    on_progress(frac, f"Rendering video… {int(frac * 100)}%")


def _render_batched(src, keep, out_path, part_path, on_log, on_progress,
                    video_opts, audio_opts, mux_opts, fade, total, logger):
    """The many-cuts render path: encode _BATCH_SIZE segments at a time — the
    input-side -ss/-to decodes only that window, and `-copyts` keeps original
    timestamps so each batch's trims select exactly the frames the single-pass
    graph would. The parts are then joined with a video stream-copy; audio rides
    the intermediates as PCM inside NUT (ffmpeg's own container — exact timestamps,
    holds every codec we emit) and is encoded once, at the join. Encoding AAC/Opus
    per part instead would pad every join with an encoder-delay tail and drift A/V
    across hundreds of segments.

    Only reached when NO fps conform is active (see _should_batch): a per-batch
    `-r` restarts the constant-frame-rate dup/drop grid at each batch's t=0, which
    does not match the single-pass graph's one continuous conform (they diverge by
    a frame at the seams). VFR normalization therefore uses the single-pass path.

    Verified against the single-pass graph, with no fps conform, by
    benchmarks/verify_render_equivalence.py: video is bit-identical (frame md5);
    audio is sample-identical except that a window's decoder may place up to one
    source-audio frame (~21 ms) of the silence at a faded-to-zero cut boundary
    differently — a constant, NON-accumulating timing offset, below the A/V
    perception threshold."""
    windows = _batch_windows(keep)
    on_log(f"Rendering in {len(windows)} passes ({len(keep)} segments)...")
    # Move the codec tag (e.g. hvc1, QuickTime-friendly HEVC) from the part encodes
    # to the final remux: NUT rejects it outright ("Tag hvc1 incompatible with
    # output codec id"), and it only means anything in the target container anyway.
    part_video_opts, tag = list(video_opts), []
    if "-tag:v" in part_video_opts:
        t = part_video_opts.index("-tag:v")
        tag = part_video_opts[t:t + 2]
        del part_video_opts[t:t + 2]
    # Monotonic progress across the passes: the parts climb to ~100% of `total`,
    # and the join stage's own out_time restarts from 0 — without the clamp the
    # bar would visibly jump backward. Also the truthful value for a failure:
    # the ladder in pipeline.py must see how far the render actually got, not
    # just how many whole batches completed (a mid-first-batch disk failure
    # would otherwise read as "encoder never started" and re-render everything).
    last = {"frac": 0.0}

    def emit(frac):
        last["frac"] = max(last["frac"], max(0.0, min(1.0, frac)))
        _emit_render_progress(on_progress, last["frac"])

    try:
        with tempfile.TemporaryDirectory(prefix="crisp-render-") as tmpdir:
            tmp = Path(tmpdir)
            parts, done = [], 0.0
            for bi, (seek, stop, segments) in enumerate(windows):
                graph = tmp / f"graph{bi:04d}.txt"
                graph.write_text("\n".join(build_filter_graph(segments, fade=fade)),
                                 encoding="utf-8")
                part = tmp / f"part{bi:04d}.nut"
                name = f"ffmpeg render {bi + 1}/{len(windows)}"
                # A window at the head of the file reads plainly — `-ss 0 -copyts`
                # changes how the demuxer applies the source's audio edit list
                # (AAC/Opus priming samples), which skewed the first window's audio
                # against a continuous decode. Seeked windows keep -copyts so trim
                # compares the same absolute timestamps the single-pass graph does.
                seek_opts = [] if seek <= 0 else ["-ss", f"{seek:.6f}"]
                copyts = [] if seek <= 0 else ["-copyts"]
                cmd = [ffmpeg_bin(), "-y", *seek_opts, "-to", f"{stop:.6f}",
                       "-i", str(src), *copyts,
                       "-filter_complex_script", str(graph),
                       "-map", "[outv]", "-map", "[outa]",
                       *part_video_opts, "-c:a", "pcm_s24le",
                       "-progress", "pipe:1", "-nostats", str(part)]
                rc, err_text = _run_ffmpeg_progress(
                    cmd, logger, name,
                    lambda secs, base=done: emit((base + secs) / total))
                logger.tool_result(name, rc, err_text if rc != 0 else "")
                if rc != 0 or not part.exists():
                    err = CleanError(f"Rendering failed.\n{err_text[-1500:]}")
                    err.render_progress = last["frac"]
                    raise err
                parts.append(part)
                done += sum(e - s for s, e in segments)

            listing = tmp / "concat.txt"
            listing.write_text(
                "\n".join("file '{}'".format(str(p).replace("'", r"'\''")) for p in parts),
                encoding="utf-8")
            # `aresample=async=1` conforms the joined audio to clean timestamps —
            # measured byte-identical output with or without it, but without it the
            # joined stream carries non-monotonic audio DTS at the part seams,
            # which players and editors complain about.
            cmd = [ffmpeg_bin(), "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
                   "-c:v", "copy", *tag, "-af", "aresample=async=1:first_pts=0",
                   *audio_opts, *mux_opts,
                   "-progress", "pipe:1", "-nostats", str(part_path)]
            rc, err_text = _run_ffmpeg_progress(
                cmd, logger, "ffmpeg render join",
                lambda secs: emit(secs / total))
            logger.tool_result("ffmpeg render join", rc, err_text if rc != 0 else "")
            if rc != 0 or not part_path.exists():
                err = CleanError(f"Rendering failed.\n{err_text[-1500:]}")
                # Every batch encoded fine; a join failure (disk, mux) won't be
                # cured by re-rendering on another encoder — never retry the ladder.
                err.render_progress = 1.0
                raise err
            os.replace(part_path, out_path)
    finally:
        part_path.unlink(missing_ok=True)  # no-op on success (already replaced away)
