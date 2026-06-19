"""Optionally demux the cleaned file into separate video-only and audio-only files.

For editors who want to treat picture and sound separately — e.g. drop the video
into a timeline to animate over it while keeping the cleaned voiceover ("walkover")
as its own track. Pure stream copy (no re-encode), so it's fast and lossless. The
combined cleaned file is always the primary deliverable; the split is best-effort.
"""

import subprocess
from pathlib import Path

from .encode import container_args
from .enginelog import EngineLogger
from .tools import ffmpeg_bin

# Audio-only container per codec when copying the stream as-is (no re-encode):
# AAC → .m4a, Opus → Ogg Opus.
_AUDIO_EXT = {"aac": "m4a", "opus": "opus"}


def split_paths(cleaned_path, audio_codec, audio_format="match"):
    """The two stem paths beside the cleaned file: `<name>_video.<ext>` (same
    container) and `<name>_audio.<ext>`. With `audio_format="wav"` the audio stem
    is a `.wav`; otherwise it matches the cleaned audio codec. Pure — no I/O."""
    cleaned = Path(cleaned_path)
    video_path = cleaned.with_name(f"{cleaned.stem}_video{cleaned.suffix}")
    audio_ext = "wav" if audio_format == "wav" else _AUDIO_EXT.get(audio_codec, "m4a")
    audio_path = cleaned.with_name(f"{cleaned.stem}_audio.{audio_ext}")
    return video_path, audio_path


def split_av(cleaned_path, audio_codec, on_log, audio_format="match", logger=None):
    """Write the video-only and audio-only stems. The video is always a stream copy
    (no re-encode); the audio is copied as-is, or re-encoded to uncompressed WAV
    when `audio_format="wav"` (what most editors prefer). Returns
    `(video_path, audio_path)` as strings; a stem that fails comes back "" (the
    combined cleaned file already exists, so a split failure never fails the clean)."""
    logger = logger or EngineLogger(None)
    try:
        cleaned = Path(cleaned_path)
        container = cleaned.suffix.lower().lstrip(".")
        video_path, audio_path = split_paths(cleaned_path, audio_codec, audio_format)
        faststart = container_args(container)
        audio_codec_args = ["-c:a", "pcm_s16le"] if audio_format == "wav" else ["-c", "copy"]

        on_log("Splitting video and audio tracks…")
        video_ok = _extract(
            [ffmpeg_bin(), "-y", "-i", str(cleaned), "-map", "0:v:0", "-an", "-c", "copy",
             *faststart, str(video_path)], video_path, "split video", logger)
        audio_ok = _extract(
            [ffmpeg_bin(), "-y", "-i", str(cleaned), "-map", "0:a:0", "-vn", *audio_codec_args,
             str(audio_path)], audio_path, "split audio", logger)

        if not video_ok:
            on_log("Couldn't write the video-only track.")
        if not audio_ok:
            on_log("Couldn't write the audio-only track (is there an audio stream?).")
        return (str(video_path) if video_ok else "", str(audio_path) if audio_ok else "")
    except Exception:
        # Best-effort: the combined cleaned file is the real deliverable, so any
        # failure here (e.g. ffmpeg can't be resolved) must never fail the clean.
        logger.exception("Track split failed")
        on_log("Couldn't split the tracks.")
        return "", ""


def _extract(cmd, out_path, label, logger):
    logger.command(f"ffmpeg {label}", cmd)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        logger.error(f"ffmpeg {label} couldn't run: {e}")
        return False
    out = Path(out_path)
    # returncode 0 alone isn't enough — guard against a 0-byte / truncated stem.
    ok = res.returncode == 0 and out.exists() and out.stat().st_size > 0
    # Splitting is best-effort (a clip with no audio track legitimately "fails"),
    # so record the exit code for every run at DEBUG rather than ERROR — and attach
    # stderr only when it didn't produce a usable file.
    detail = "" if ok else (res.stderr or "").strip()
    logger.debug(f"ffmpeg {label} exited {res.returncode}"
                 + (f"\n{detail[-2000:]}" if detail else ""))
    return ok
