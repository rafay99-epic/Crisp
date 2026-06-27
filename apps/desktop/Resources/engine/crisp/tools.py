"""Locating and probing the external tools the engine drives."""

import os
import shutil
import subprocess
from pathlib import Path

from .errors import CleanError


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


def which_filler():
    """The bundled Core ML filler-classifier helper (an opt-in alternative to
    whisper for filler detection). Resolved from CRISP_FILLER (set by the app to
    the bundled binary), falling back to PATH for a dev build."""
    return _resolve_tool("CRISP_FILLER", ("crisp-filler",),
                         "The filler-classifier helper ships with the Crisp app.")


def probe_video_fps(path: Path, logger=None):
    """The first video stream's base (``r_frame_rate``) and average
    (``avg_frame_rate``) rates, as raw ffprobe fraction strings (``"30000/1001"``).
    Returns ``("", "")`` when there's no video stream or the probe fails — the
    caller (crisp.framerate) treats unknown rates as "don't normalize", so a probe
    failure degrades to the source's own timing rather than breaking the clean.

    `logger` is optional (a no-op when None), mirroring `ffprobe_duration` — the
    rest of this module logs only through a passed-in logger."""
    res = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate,avg_frame_rate",
         "-of", "default=noprint_wrappers=1", str(path)],
        capture_output=True, text=True,
    )
    # Fail open: on a nonzero exit return ("", "") so a partial/garbled stdout can't
    # feed bad metadata into resolve_target_fps (which would then normalize on the
    # very path that's supposed to leave the source untouched).
    if res.returncode != 0:
        if logger is not None:
            logger.error(f"ffprobe couldn't read frame rate of {path} (exit {res.returncode})\n"
                         f"{(res.stderr or '').strip()[-800:]}")
        return "", ""
    r = avg = ""
    for line in res.stdout.splitlines():
        s = line.strip()
        if s.startswith("r_frame_rate="):
            r = s.split("=", 1)[1].strip()
        elif s.startswith("avg_frame_rate="):
            avg = s.split("=", 1)[1].strip()
    return r, avg


def ffprobe_duration(path: Path, logger=None) -> float:
    out = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(out.stdout.strip())
    except ValueError:
        # The caller turns 0.0 into a generic "couldn't read duration" error; log
        # the real ffprobe stderr here so the cause isn't lost.
        if logger is not None:
            logger.error(f"ffprobe couldn't read duration of {path} (exit {out.returncode})\n"
                         f"{(out.stderr or '').strip()[-800:]}")
        return 0.0
