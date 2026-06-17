#!/usr/bin/env python3
"""
clean_video.py — Remove silent pauses and filler words ("um", "uh", "hmm", ...)
from a screen-recording / talking-head video.

Can be used two ways:
  • As a command:   python3 clean_video.py video.mkv [options]
  • As a library:   from clean_video import clean_video  (used by the GUI app)

What it does, in order:
  1. Makes a safe BACKUP copy of your original file (never touched again).
  2. Detects pauses/silence from the real audio energy (accurate).
  3. Transcribes the audio with whisper.cpp to find filler words.
  4. Re-renders a new "<name>_cleaned.mp4" with pauses + fillers removed,
     keeping audio and video perfectly in sync.

Nothing is ever deleted. Your original stays where it was, plus a backup copy
is written to an "_originals" folder next to it.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ----------------------------------------------------------------------------
# Configuration defaults (all overridable)
# ----------------------------------------------------------------------------

# Words treated as "fillers" and removed. Compared after lower-casing and
# stripping punctuation. Kept to non-words / hesitations so we don't cut real
# speech. Edit this list to taste.
DEFAULT_FILLERS = {
    "um", "umm", "ummm",
    "uh", "uhh", "uhhh",
    "erm", "er", "err",
    "hmm", "hm", "hmmm",
    "mm", "mmm",
    "ah", "ahh", "ahem",
    "aw", "aww", "awww",
    "uhm", "mhm",
}

DEFAULT_MAX_PAUSE = 0.6       # cut silences longer than this (seconds)
DEFAULT_NOISE_DB = -30        # audio below this loudness (dB) counts as silence
DEFAULT_KEEP_PAUSE = 0.15     # breathing room left around each cut (seconds)
MIN_KEEP = 0.05               # drop kept fragments shorter than this (seconds)

HERE = Path(__file__).resolve().parent
DEFAULT_MODEL = HERE / "models" / "ggml-base.en.bin"


# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------

class CleanError(Exception):
    """Raised on any failure; carries a human-readable message."""


def _noop(*_a, **_k):
    pass


def _resolve_tool(env_var: str, candidates: tuple, hint: str) -> str:
    """Locate an external tool. The Swift app passes absolute paths to the
    binaries it bundles via env vars (CRISP_FFMPEG / CRISP_FFPROBE / CRISP_WHISPER);
    falling back to PATH keeps the plain `python3 clean_video.py …` CLI and a
    developer's Homebrew install working unchanged."""
    override = os.environ.get(env_var)
    if override and Path(override).exists():
        return override
    for name in candidates:
        path = shutil.which(name)
        if path:
            return path
    raise CleanError(f"{candidates[0]} not found. {hint}")


def ffmpeg_bin() -> str:
    return _resolve_tool("CRISP_FFMPEG", ("ffmpeg",), "Install it with:  brew install ffmpeg")


def ffprobe_bin() -> str:
    return _resolve_tool("CRISP_FFPROBE", ("ffprobe",), "Install it with:  brew install ffmpeg")


def which_whisper():
    return _resolve_tool("CRISP_WHISPER", ("whisper-cli", "whisper-cpp", "main"),
                         "Install it with:  brew install whisper-cpp")


def ffprobe_duration(path: Path) -> float:
    out = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


def normalize_word(text: str) -> str:
    return text.strip().strip(".,!?;:\"'()[]…-–—").lower()


# ----------------------------------------------------------------------------
# Step 1 — Backup
# ----------------------------------------------------------------------------

def make_backup(src: Path, on_log) -> Path:
    backup_dir = src.parent / "_originals"
    backup_dir.mkdir(exist_ok=True)
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


# ----------------------------------------------------------------------------
# Step 2 — Audio extraction + silence detection
# ----------------------------------------------------------------------------

def extract_audio(src: Path, wav_path: Path, on_log) -> None:
    on_log("Extracting audio for analysis...")
    res = subprocess.run(
        [ffmpeg_bin(), "-y", "-i", str(src),
         "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(wav_path)],
        capture_output=True, text=True,
    )
    if res.returncode != 0 or not wav_path.exists():
        raise CleanError(f"Could not extract audio.\n{res.stderr[-800:]}")


def detect_silences(wav_path: Path, noise_db: float, min_pause: float, on_log) -> list:
    on_log("Detecting pauses / silence...")
    res = subprocess.run(
        [ffmpeg_bin(), "-i", str(wav_path),
         "-af", f"silencedetect=noise={noise_db}dB:d={min_pause}",
         "-f", "null", "-"],
        capture_output=True, text=True,
    )
    silences, start = [], None
    for line in res.stderr.splitlines():
        line = line.strip()
        if "silence_start:" in line:
            try:
                start = float(line.split("silence_start:")[1].strip().split()[0])
            except (IndexError, ValueError):
                start = None
        elif "silence_end:" in line and start is not None:
            try:
                end = float(line.split("silence_end:")[1].strip().split()[0])
                silences.append((start, end))
            except (IndexError, ValueError):
                pass
            start = None
    return silences


# ----------------------------------------------------------------------------
# Step 3 — Transcribe (for filler words), with live progress
# ----------------------------------------------------------------------------

def transcribe(whisper_bin, model, wav_path, out_prefix, on_log, on_progress):
    on_log("Transcribing (finding filler words)... this is the slow step.")
    json_path = Path(str(out_prefix) + ".json")
    proc = subprocess.Popen(
        [whisper_bin, "-m", str(model), "-f", str(wav_path),
         "-ml", "1", "-sow", "-oj", "-of", str(out_prefix), "-pp"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    for line in proc.stderr:
        if "progress =" in line:
            try:
                pct = int(line.split("progress =")[1].strip().split("%")[0])
                on_progress(pct / 100.0, f"Transcribing… {pct}%")
            except (IndexError, ValueError):
                pass
    proc.wait()
    if not json_path.exists():
        raise CleanError("Transcription failed — the speech model may be missing.")
    with open(json_path) as f:
        data = json.load(f)
    words = []
    for seg in data.get("transcription", []):
        o = seg.get("offsets", {})
        try:
            start, end = float(o["from"]) / 1000.0, float(o["to"]) / 1000.0
        except (KeyError, TypeError, ValueError):
            continue
        if seg.get("text", "").strip():
            words.append({"text": seg["text"], "start": start, "end": end})
    return words


# ----------------------------------------------------------------------------
# Step 4 — Decide what to cut
# ----------------------------------------------------------------------------

def build_keep_segments(words, silences, duration, fillers, keep_pause):
    """Return (keep, stats): list of (start, end) seconds to KEEP, plus counts."""
    remove = []
    stats = {"fillers": 0, "pauses": 0}

    for s, e in silences:                       # pauses (trim middle of silence)
        inner_s, inner_e = s + keep_pause, e - keep_pause
        if inner_e - inner_s > 0.01:
            remove.append((inner_s, inner_e))
            stats["pauses"] += 1

    for w in words:                             # filler words (exact span)
        if normalize_word(w["text"]) in fillers:
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
        if s - cursor >= MIN_KEEP:
            keep.append((cursor, s))
        cursor = max(cursor, e)
    if duration - cursor >= MIN_KEEP:
        keep.append((cursor, duration))
    return keep, stats


# ----------------------------------------------------------------------------
# Step 5 — Render the cleaned video, with live progress
# ----------------------------------------------------------------------------

def render(src, keep, out_path, on_log, on_progress):
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
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart",
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


# ----------------------------------------------------------------------------
# Public engine entry point (used by both the CLI and the GUI app)
# ----------------------------------------------------------------------------

def clean_video(src, out_path=None, model=None, pause=DEFAULT_MAX_PAUSE,
                noise=DEFAULT_NOISE_DB, keep_pause=DEFAULT_KEEP_PAUSE,
                remove_fillers=True, on_log=None, on_progress=None):
    """
    Clean one video. Returns a dict with results.
      on_log(str)            — called with human-readable status lines.
      on_progress(frac, str) — called with 0.0..1.0 overall progress + label.
    """
    on_log = on_log or _noop
    on_progress = on_progress or _noop

    src = Path(src).expanduser().resolve()
    if not src.exists():
        raise CleanError(f"File not found: {src}")

    model = Path(model).expanduser().resolve() if model else DEFAULT_MODEL
    out_path = (Path(out_path).expanduser().resolve() if out_path
                else src.with_name(f"{src.stem}_cleaned.mp4"))

    fillers = DEFAULT_FILLERS if remove_fillers else set()
    whisper_bin = None
    if fillers:
        if not model.exists():
            raise CleanError(f"Speech model not found: {model}\nRun setup.sh to download it.")
        whisper_bin = which_whisper()

    # Overall progress is split across stages so the bar moves sensibly.
    def stage(lo, hi):
        return lambda f, label="": on_progress(lo + (hi - lo) * f, label)

    on_log(f"=== Cleaning: {src.name} ===")
    on_progress(0.0, "Starting…")

    backup = make_backup(src, on_log)
    on_progress(0.03, "Backed up original")

    duration = ffprobe_duration(src)
    if duration <= 0:
        raise CleanError("Could not read the video's duration — is it a valid video file?")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        wav = tmp / "audio.wav"

        extract_audio(src, wav, on_log)
        on_progress(0.08, "Audio extracted")

        silences = detect_silences(wav, noise, pause, on_log)
        on_progress(0.15, "Pauses detected")

        words = []
        if fillers:
            words = transcribe(whisper_bin, model, wav, tmp / "transcript",
                               on_log, stage(0.15, 0.58))
            on_log(f"Found {len(words)} spoken words.")
        on_progress(0.58, "Planning cuts…")

        keep, stats = build_keep_segments(words, silences, duration, fillers, keep_pause)
        if not keep:
            raise CleanError("Everything looked like silence — nothing to keep. "
                             "Try a larger pause value.")

        kept_dur = sum(e - s for s, e in keep)
        on_log(f"Removing {stats['fillers']} filler words and {stats['pauses']} pauses.")
        on_log(f"{duration:.0f}s  →  {kept_dur:.0f}s  (saved {duration - kept_dur:.0f}s)")

        render(src, keep, out_path, on_log, stage(0.60, 1.0))

    on_progress(1.0, "Done")
    on_log(f"✅ Done! Cleaned video: {out_path}")
    return {
        "input": str(src),
        "output": str(out_path),
        "backup": str(backup),
        "orig_seconds": duration,
        "new_seconds": kept_dur,
        "saved_seconds": duration - kept_dur,
        "fillers": stats["fillers"],
        "pauses": stats["pauses"],
    }


# ----------------------------------------------------------------------------
# Command-line interface
# ----------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description="Remove pauses and filler words from a video.")
    p.add_argument("video", help="path to the input video file")
    p.add_argument("--model", default=str(DEFAULT_MODEL), help="whisper.cpp model file (.bin)")
    p.add_argument("--pause", type=float, default=DEFAULT_MAX_PAUSE,
                   help=f"cut silences longer than this many seconds (default {DEFAULT_MAX_PAUSE})")
    p.add_argument("--noise", type=float, default=DEFAULT_NOISE_DB,
                   help=f"loudness (dB) below which audio counts as silence (default {DEFAULT_NOISE_DB})")
    p.add_argument("--keep-pause", type=float, default=DEFAULT_KEEP_PAUSE,
                   help=f"breathing room left around each cut, in seconds (default {DEFAULT_KEEP_PAUSE})")
    p.add_argument("--no-fillers", action="store_true", help="only remove pauses, keep um/uh")
    p.add_argument("--out", default=None, help="output path (default: <name>_cleaned.mp4 beside input)")
    p.add_argument("--ndjson", action="store_true",
                   help="emit machine-readable progress as one JSON object per line "
                        "(used by the desktop app)")
    args = p.parse_args()

    if args.ndjson:
        def emit(obj):
            print(json.dumps(obj), flush=True)
        on_log = lambda m: emit({"event": "log", "message": m})
        on_progress = lambda f, l="": emit({"event": "progress", "fraction": f, "label": l})
    else:
        def on_log(msg):
            print(f"→ {msg}" if not msg.startswith(("=", "✅")) else f"\n{msg}", flush=True)
        on_progress = None

    try:
        result = clean_video(args.video, out_path=args.out, model=args.model, pause=args.pause,
                             noise=args.noise, keep_pause=args.keep_pause,
                             remove_fillers=not args.no_fillers,
                             on_log=on_log, on_progress=on_progress)
        if args.ndjson:
            emit({"event": "result", **result})
    except CleanError as e:
        if args.ndjson:
            emit({"event": "error", "message": str(e)})
        else:
            print(f"ERROR: {e}", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
