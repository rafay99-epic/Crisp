"""The public engine entry point — orchestrates detect → edit into a clean video."""

import tempfile
from pathlib import Path

from .config import (
    DEFAULT_AUDIO_BITRATE, DEFAULT_AUDIO_CODEC, DEFAULT_BACKUP, DEFAULT_CONTAINER, DEFAULT_HARDWARE,
    DEFAULT_KEEP_PAUSE, DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB, DEFAULT_QUALITY,
    DEFAULT_VIDEO_CODEC, MIN_KEEP,
)
from .detect import detect_silences, extract_audio, transcribe
from .edit import build_keep_segments, make_backup, render, tag_output_source, unique_output_path
from .encode import (
    audio_args, container_args, default_output_path, resolve_codecs, resolve_container, video_args,
)
from .enginelog import EngineLogger
from .errors import CleanError
from .tools import ffprobe_duration, which_whisper


def _noop(*_a, **_k):
    pass


# Analyze-only captures every candidate gap down to this floor; the app applies the
# real (larger) pause threshold itself, so changing it needs no re-analysis.
ANALYZE_MIN_PAUSE = 0.05


def analyze(src, noise=DEFAULT_NOISE_DB, buckets=240, on_log=None, logger=None):
    """Analyze-only: extract audio, find candidate silences at `noise`, and summarize
    the waveform — no transcription, no render. Returns {duration, peaks, silences}.
    The desktop app drives this for the live cut preview and recomputes the cut
    regions itself as the user drags the knobs."""
    on_log = on_log or _noop
    logger = logger or EngineLogger(None)

    src = Path(src).expanduser().resolve()
    if not src.exists():
        raise CleanError(f"File not found: {src}")

    logger.info(f"analyze src={src} noise={noise} buckets={buckets}")
    duration = ffprobe_duration(src, logger=logger)
    if duration <= 0:
        raise CleanError("Could not read the video's duration — is it a valid video file?")

    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "audio.wav"
        extract_audio(src, wav, on_log, logger=logger)
        silences = detect_silences(wav, noise, ANALYZE_MIN_PAUSE, on_log, logger=logger)
        from .waveform import waveform_summary
        peaks = waveform_summary(wav, duration, [(0.0, duration)], buckets)["peaks"]

    return {"duration": duration, "peaks": peaks,
            "silences": [[s, e] for s, e in silences]}


def clean_video(src, out_path=None, model=None, pause=DEFAULT_MAX_PAUSE,
                noise=DEFAULT_NOISE_DB, keep_pause=DEFAULT_KEEP_PAUSE, min_keep=MIN_KEEP,
                video_codec=DEFAULT_VIDEO_CODEC, hardware=DEFAULT_HARDWARE, quality=DEFAULT_QUALITY,
                audio_codec=DEFAULT_AUDIO_CODEC, audio_bitrate=DEFAULT_AUDIO_BITRATE,
                container=DEFAULT_CONTAINER, remove_fillers=True, backup=DEFAULT_BACKUP,
                backup_dir=None, out_dir=None, split_tracks=False, split_audio="match",
                waveform_buckets=0, keep_file=None, on_log=None, on_progress=None, logger=None):
    """
    Clean one video. Returns a dict with results.
      on_log(str)            — called with human-readable status lines.
      on_progress(frac, str) — called with 0.0..1.0 overall progress + label.
      logger                 — optional EngineLogger for detailed file logging
                               (commands, tool stderr); defaults to a no-op.
    """
    on_log = on_log or _noop
    on_progress = on_progress or _noop
    logger = logger or EngineLogger(None)

    src = Path(src).expanduser().resolve()
    if not src.exists():
        raise CleanError(f"File not found: {src}")

    model = Path(model).expanduser().resolve() if model else DEFAULT_MODEL
    if out_path:
        # An explicit output path wins; its extension picks the container.
        out_path = Path(out_path).expanduser().resolve()
        container = out_path.suffix.lower().lstrip(".") or "mp4"
    else:
        # Otherwise: the chosen container, or "auto" = match the input's. The
        # cleaned file lands in out_dir if one was chosen (e.g. a NAS), else beside
        # the source.
        container = resolve_container(container, src.suffix)
        out_path = default_output_path(src, container, out_dir).resolve()
        if out_dir:
            try:
                out_path.parent.mkdir(parents=True, exist_ok=True)
            except OSError as e:
                raise CleanError(f"Couldn't use the output folder \"{out_path.parent}\". "
                                 f"Is the drive connected and writable?\n{e}")
            # In a shared folder, don't clobber a different source's cleaned file.
            out_path = unique_output_path(out_path, src)

    # The container dictates which codecs are legal (e.g. WebM forces VP9 + Opus);
    # coerce now and tell the user about any swap rather than letting ffmpeg fail.
    video_codec, audio_codec, hardware, codec_notes = resolve_codecs(
        container, video_codec, audio_codec, hardware)

    logger.info(f"src={src}")
    logger.info(f"out={out_path} container={container} video={video_codec} "
                f"audio={audio_codec} hw={hardware} quality={quality} "
                f"remove_fillers={remove_fillers} keep_file={bool(keep_file)} backup={backup}")

    # An explicit reviewed keep-list (the app's edit-timeline output) bypasses
    # detection entirely — no audio analysis, no transcription, no model — so we
    # render exactly the segments the user approved.
    need_transcript = remove_fillers and not keep_file
    whisper_bin = None
    if need_transcript:
        if not model.exists():
            raise CleanError(f"Speech model not found: {model}\nRun setup.sh to download it.")
        whisper_bin = which_whisper()
        logger.info(f"model={model} whisper={whisper_bin}")

    # Overall progress is split across stages so the bar moves sensibly.
    def stage(lo, hi):
        return lambda f, label="": on_progress(lo + (hi - lo) * f, label)

    on_log(f"=== Cleaning: {src.name} ===")
    for note in codec_notes:
        on_log(note)
    on_progress(0.0, "Starting…")

    backup_path = make_backup(src, on_log, backup_dir, logger=logger) if backup else None
    if backup_path:
        on_progress(0.03, "Backed up original")

    duration = ffprobe_duration(src, logger=logger)
    if duration <= 0:
        raise CleanError("Could not read the video's duration — is it a valid video file?")
    logger.info(f"duration={duration:.2f}s")

    # The waveform (peaks + cut mask) is built from the analysis WAV; the reviewed
    # keep-list path skips analysis, so it has no waveform (the done row falls back to
    # the simpler reduction bar).
    wave_summary = {"peaks": [], "removed": []}

    if keep_file:
        from .edit import load_keep_segments
        keep = load_keep_segments(keep_file, duration)
        # The user decided the cuts; report how many removed gaps the keep-list implies
        # (a leading/trailing trim and each interior gap), so the summary still reads.
        cuts = sum(1 for i in range(len(keep) - 1) if keep[i + 1][0] - keep[i][1] > 0.01)
        if keep[0][0] > 0.01:
            cuts += 1
        if keep[-1][1] < duration - 0.01:
            cuts += 1
        stats = {"fillers": 0, "pauses": cuts}
        on_log(f"Using {len(keep)} reviewed segment(s).")
        on_progress(0.58, "Rendering reviewed cuts…")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            wav = tmp / "audio.wav"

            extract_audio(src, wav, on_log, logger=logger)
            on_progress(0.08, "Audio extracted")

            silences = detect_silences(wav, noise, pause, on_log, logger=logger)
            on_progress(0.15, "Pauses detected")

            words = []
            if remove_fillers:
                words = transcribe(whisper_bin, model, wav, tmp / "transcript",
                                   on_log, stage(0.15, 0.58), logger=logger)
                on_log(f"Found {len(words)} spoken words.")
            on_progress(0.58, "Planning cuts…")

            keep, stats = build_keep_segments(words, silences, duration, keep_pause, min_keep)
            if not keep:
                raise CleanError("Everything looked like silence — nothing to keep. "
                                 "Try a larger pause value.")

            # Build the UI waveform now, while the analysis WAV still exists (it's
            # deleted when this temp dir closes). Opt-in via waveform_buckets so the
            # bare CLI / watcher don't pay for data nothing renders.
            if waveform_buckets > 0:
                from .waveform import waveform_summary
                wave_summary = waveform_summary(wav, duration, keep, waveform_buckets)

    kept_dur = sum(e - s for s, e in keep)
    logger.info(f"keep {len(keep)} segments, kept {kept_dur:.2f}s, "
                f"fillers={stats['fillers']} pauses={stats['pauses']}")
    on_log(f"Removing {stats['fillers']} filler words and {stats['pauses']} pauses.")
    on_log(f"{duration:.0f}s  →  {kept_dur:.0f}s  (saved {duration - kept_dur:.0f}s)")

    audio = audio_args(audio_codec, audio_bitrate)
    mux = container_args(container)
    try:
        render(src, keep, out_path, on_log, stage(0.60, 1.0),
               video_args(video_codec, hardware, quality), audio, mux, logger=logger)
    except CleanError:
        if not hardware:
            raise
        # Hardware encoding can be unavailable in odd setups (e.g. a macOS VM
        # with no media engine). Fall back to software so a clean never fails.
        logger.notice("Hardware encoding failed — retrying in software")
        on_log("Hardware encoding failed — falling back to software encoding…")
        render(src, keep, out_path, on_log, stage(0.60, 1.0),
               video_args(video_codec, False, quality), audio, mux, logger=logger)

    if out_dir:
        # Tag the output so a later re-clean of this same source overwrites it,
        # while a different same-named source gets its own _N copy.
        tag_output_source(out_path, src)

    # Optionally demux the cleaned file into separate video-only / audio-only stems
    # (stream copy, fast) for editors that animate the picture over the voiceover.
    video_out, audio_out = "", ""
    if split_tracks:
        from .split import split_av
        video_out, audio_out = split_av(out_path, audio_codec, on_log,
                                        audio_format=split_audio, logger=logger)

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
        "peaks": wave_summary["peaks"],
        "removed": wave_summary["removed"],
        "video_output": video_out,
        "audio_output": audio_out,
    }
