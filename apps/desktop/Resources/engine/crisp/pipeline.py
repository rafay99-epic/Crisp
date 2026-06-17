"""The public engine entry point — orchestrates detect → edit into a clean video."""

import tempfile
from pathlib import Path

from .config import (
    DEFAULT_AUDIO_BITRATE, DEFAULT_AUDIO_CODEC, DEFAULT_BACKUP, DEFAULT_CONTAINER, DEFAULT_HARDWARE,
    DEFAULT_KEEP_PAUSE, DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB, DEFAULT_QUALITY,
    DEFAULT_VIDEO_CODEC, MIN_KEEP,
)
from .detect import detect_silences, extract_audio, transcribe
from .edit import build_keep_segments, make_backup, render
from .encode import audio_args, container_args, resolve_codecs, resolve_container, video_args
from .errors import CleanError
from .tools import ffprobe_duration, which_whisper


def _noop(*_a, **_k):
    pass


def clean_video(src, out_path=None, model=None, pause=DEFAULT_MAX_PAUSE,
                noise=DEFAULT_NOISE_DB, keep_pause=DEFAULT_KEEP_PAUSE, min_keep=MIN_KEEP,
                video_codec=DEFAULT_VIDEO_CODEC, hardware=DEFAULT_HARDWARE, quality=DEFAULT_QUALITY,
                audio_codec=DEFAULT_AUDIO_CODEC, audio_bitrate=DEFAULT_AUDIO_BITRATE,
                container=DEFAULT_CONTAINER, remove_fillers=True, backup=DEFAULT_BACKUP,
                backup_dir=None, on_log=None, on_progress=None):
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
    if out_path:
        # An explicit output path wins; its extension picks the container.
        out_path = Path(out_path).expanduser().resolve()
        container = out_path.suffix.lower().lstrip(".") or "mp4"
    else:
        # Otherwise: the chosen container, or "auto" = match the input's.
        container = resolve_container(container, src.suffix)
        out_path = src.with_name(f"{src.stem}_cleaned.{container}")

    # The container dictates which codecs are legal (e.g. WebM forces VP9 + Opus);
    # coerce now and tell the user about any swap rather than letting ffmpeg fail.
    video_codec, audio_codec, hardware, codec_notes = resolve_codecs(
        container, video_codec, audio_codec, hardware)

    whisper_bin = None
    if remove_fillers:
        if not model.exists():
            raise CleanError(f"Speech model not found: {model}\nRun setup.sh to download it.")
        whisper_bin = which_whisper()

    # Overall progress is split across stages so the bar moves sensibly.
    def stage(lo, hi):
        return lambda f, label="": on_progress(lo + (hi - lo) * f, label)

    on_log(f"=== Cleaning: {src.name} ===")
    for note in codec_notes:
        on_log(note)
    on_progress(0.0, "Starting…")

    backup_path = make_backup(src, on_log, backup_dir) if backup else None
    if backup_path:
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
        if remove_fillers:
            words = transcribe(whisper_bin, model, wav, tmp / "transcript",
                               on_log, stage(0.15, 0.58))
            on_log(f"Found {len(words)} spoken words.")
        on_progress(0.58, "Planning cuts…")

        keep, stats = build_keep_segments(words, silences, duration, keep_pause, min_keep)
        if not keep:
            raise CleanError("Everything looked like silence — nothing to keep. "
                             "Try a larger pause value.")

        kept_dur = sum(e - s for s, e in keep)
        on_log(f"Removing {stats['fillers']} filler words and {stats['pauses']} pauses.")
        on_log(f"{duration:.0f}s  →  {kept_dur:.0f}s  (saved {duration - kept_dur:.0f}s)")

        audio = audio_args(audio_codec, audio_bitrate)
        mux = container_args(container)
        try:
            render(src, keep, out_path, on_log, stage(0.60, 1.0),
                   video_args(video_codec, hardware, quality), audio, mux)
        except CleanError:
            if not hardware:
                raise
            # Hardware encoding can be unavailable in odd setups (e.g. a macOS VM
            # with no media engine). Fall back to software so a clean never fails.
            on_log("Hardware encoding failed — falling back to software encoding…")
            render(src, keep, out_path, on_log, stage(0.60, 1.0),
                   video_args(video_codec, False, quality), audio, mux)

    on_progress(1.0, "Done")
    on_log(f"✅ Done! Cleaned video: {out_path}")
    return {
        "input": str(src),
        "output": str(out_path),
        "backup": str(backup_path) if backup_path else "",
        "orig_seconds": duration,
        "new_seconds": kept_dur,
        "saved_seconds": duration - kept_dur,
        "fillers": stats["fillers"],
        "pauses": stats["pauses"],
    }
