#!/usr/bin/env python3
"""
clean_video.py — CLI entry for the Crisp cleaning engine.

Removes silent pauses and filler words ("um", "uh", "hmm", ...) from a
screen-recording / talking-head video, re-rendering a tight cut. Nothing is ever
deleted — your original is copied to an "_originals" folder beside it first.

The engine itself lives in the `crisp` package next to this file; this script is
just the command-line wrapper the desktop app drives:

    python3 clean_video.py video.mkv [options] [--ndjson]

Library users can skip the CLI and import the package directly:

    from crisp import clean_video
"""

import argparse
import json
import os
import shlex
import signal
import sys
from pathlib import Path

# Ensure the sibling `crisp` package is importable however this script is invoked.
sys.path.insert(0, str(Path(__file__).resolve().parent))


def _enable_group_cancel():
    """Put this run in its own process group and, on SIGTERM, take the whole group
    (this process + the ffmpeg/whisper children it spawns) down with it. Without
    this, the Swift app terminating us would orphan the encoder, which would keep
    running. Only used in --ndjson (app) mode so a terminal user keeps normal
    Ctrl-C job control."""
    os.setpgrp()

    def _handler(_signum, _frame):
        try:
            os.killpg(os.getpgrp(), signal.SIGKILL)
        finally:
            os._exit(1)

    signal.signal(signal.SIGTERM, _handler)

from crisp import CleanError, clean_video
from crisp.config import (
    DEFAULT_AUDIO_BITRATE, DEFAULT_AUDIO_CODEC, DEFAULT_COLOR_DEPTH, DEFAULT_CONTAINER,
    DEFAULT_CROSSFADE_MS, DEFAULT_EXPORT_TIMELINE, DEFAULT_FADE_MS, DEFAULT_FILLER_BACKEND, DEFAULT_FPS,
    DEFAULT_FPS_MODE, DEFAULT_KEEP_PAUSE, DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB,
    DEFAULT_QUALITY, DEFAULT_RETAKE_SENSITIVITY, DEFAULT_SNAP_MS, DEFAULT_STUDIO_SOUND,
    DEFAULT_VIDEO_CODEC, MIN_KEEP,
    RETAKE_SENSITIVITY_MIN_RUN,
)
from crisp.encode import SUPPORTED_CONTAINERS
from crisp.enginelog import logger_from_env


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
    p.add_argument("--min-keep", type=float, default=MIN_KEEP,
                   help=f"drop kept fragments shorter than this many seconds (default {MIN_KEEP})")
    p.add_argument("--studio-sound", action="store_true", default=DEFAULT_STUDIO_SOUND,
                   help=f"apply denoising + loudness normalization to audio "
                        f"(default {DEFAULT_STUDIO_SOUND})")
    p.add_argument("--no-studio-sound", action="store_false", dest="studio_sound",
                   help="disable studio sound even when the default is on")
    p.add_argument("--fade-ms", type=float, default=DEFAULT_FADE_MS,
                   help=f"audio fade in/out at each cut so joins don't click, in ms "
                        f"(0 = off; default {DEFAULT_FADE_MS})")
    p.add_argument("--crossfade-ms", type=float, default=DEFAULT_CROSSFADE_MS,
                   help=f"dissolve consecutive segments (matched video+audio crossfade) "
                        f"instead of hard cuts, in ms (0 = off; default {DEFAULT_CROSSFADE_MS})")
    p.add_argument("--snap-ms", type=float, default=DEFAULT_SNAP_MS,
                   help=f"snap each cut boundary to the nearest audio zero-crossing within "
                        f"±this window, in ms (0 = off; default {DEFAULT_SNAP_MS})")
    p.add_argument("--video-codec", choices=["h264", "hevc", "vp9"], default=DEFAULT_VIDEO_CODEC,
                   help=f"video encoder; vp9 is for WebM (default {DEFAULT_VIDEO_CODEC})")
    p.add_argument("--hardware", action="store_true",
                   help="use Apple VideoToolbox hardware encoding (faster)")
    p.add_argument("--quality", choices=["maximum", "high", "balanced", "smaller"],
                   default=DEFAULT_QUALITY, help=f"encode quality level (default {DEFAULT_QUALITY})")
    p.add_argument("--audio-codec", choices=["aac", "opus"], default=DEFAULT_AUDIO_CODEC,
                   help=f"audio encoder (default {DEFAULT_AUDIO_CODEC})")
    p.add_argument("--audio-bitrate", type=int, default=DEFAULT_AUDIO_BITRATE,
                   help=f"audio bitrate in kbps (default {DEFAULT_AUDIO_BITRATE})")
    p.add_argument("--container", choices=["auto", *SUPPORTED_CONTAINERS],
                   default=DEFAULT_CONTAINER,
                   help=f"output container; 'auto' matches the input, 'webm' uses VP9+Opus "
                        f"(default {DEFAULT_CONTAINER})")
    p.add_argument("--color-depth", choices=["auto", "8", "10"], default=DEFAULT_COLOR_DEPTH,
                   help=f"output bit depth: 'auto' matches the source (never downgrades "
                        f"10-bit/HDR footage), '8' forces 8-bit 4:2:0, '10' forces a 10-bit "
                        f"encode (default {DEFAULT_COLOR_DEPTH})")
    p.add_argument("--fps-mode", choices=["auto", "passthrough", "constant"], default=DEFAULT_FPS_MODE,
                   help="frame-rate handling: 'auto' normalizes a variable-frame-rate "
                        "(VFR) source — e.g. a screen recording — to a constant rate so "
                        "A/V stays in sync; 'passthrough' keeps the source timing; "
                        "'constant' always forces --fps "
                        f"(default {DEFAULT_FPS_MODE})")
    p.add_argument("--fps", type=float, default=DEFAULT_FPS,
                   help="target constant frame rate for --fps-mode=constant (e.g. 30, 60) "
                        "— required in that mode (0 is unset and errors). 'auto' ignores "
                        "this and uses the source's own rate")
    p.add_argument("--export-timeline", choices=["none", "fcpxml"], default=DEFAULT_EXPORT_TIMELINE,
                   help="instead of rendering a video, write a non-destructive editor "
                        "project: a copy of the original (CFR sources copied as-is; "
                        "variable-frame-rate sources conformed to CFR) + an .fcpxml timeline "
                        "that DaVinci Resolve opens to finish the cut. No final render "
                        f"(default {DEFAULT_EXPORT_TIMELINE})")
    p.add_argument("--project-dir", default=None,
                   help="folder to write the editor project into when --export-timeline "
                        "is set (default: a '<name> (Crisp)' folder beside the input)")
    p.add_argument("--no-fillers", action="store_true", help="only remove pauses, keep um/uh")
    p.add_argument("--no-retakes", action="store_true",
                   help="don't remove repeated takes (a flubbed phrase you immediately "
                        "said again); on by default, needs a whisper transcript")
    p.add_argument("--retake-sensitivity", choices=list(RETAKE_SENSITIVITY_MIN_RUN),
                   default=DEFAULT_RETAKE_SENSITIVITY,
                   help=f"how eagerly to cut repeated takes: gentle (only long redos "
                        f"after a pause) … aggressive (also mid-sentence restarts with "
                        f"no pause) (default {DEFAULT_RETAKE_SENSITIVITY})")
    p.add_argument("--no-backup", action="store_true",
                   help="don't copy the original aside before cutting")
    p.add_argument("--split", action="store_true",
                   help="also write separate video-only and audio-only files beside "
                        "the cleaned output (for editing the picture and audio apart)")
    p.add_argument("--split-audio", choices=["match", "wav"], default="match",
                   help="audio-only track format when --split is set: 'match' copies "
                        "the cleaned audio (m4a/opus), 'wav' re-encodes to PCM WAV")
    p.add_argument("--backup-dir", default=None,
                   help="folder to copy the original into (default: an '_originals' folder beside it)")
    p.add_argument("--out", default=None,
                   help="output path (default: <name>_cleaned.<ext> beside input, ext per --container)")
    p.add_argument("--out-dir", default=None,
                   help="folder to write the cleaned file into, keeping the "
                        "<name>_cleaned.<ext> name (default: beside the input)")
    p.add_argument("--ndjson", action="store_true",
                   help="emit machine-readable progress as one JSON object per line "
                        "(used by the desktop app)")
    p.add_argument("--waveform", type=int, default=0, metavar="N",
                   help="also emit an N-bucket audio waveform (peaks + which slices "
                        "were cut) in the result, for the app to render (0 = off)")
    p.add_argument("--captions", choices=["none", "srt", "vtt", "both"], default="none",
                   help="also write subtitle sidecar files (re-timed to the cleaned "
                        "video) beside the output: SubRip (.srt), WebVTT (.vtt), or both")
    p.add_argument("--filler-backend", choices=["whisper", "coreml"], default=DEFAULT_FILLER_BACKEND,
                   help="how to find filler words: 'whisper' (transcribe) or 'coreml' "
                        "(fast on-device classifier via --filler-model)")
    p.add_argument("--filler-model", default=None,
                   help="Core ML filler model (.mlmodel) used when --filler-backend=coreml")
    p.add_argument("--log-dir", default=None,
                   help="folder to write a detailed run log into (default: the "
                        "CRISP_LOG_DIR env var the desktop app sets; off if neither)")
    p.add_argument("--analyze", action="store_true",
                   help="analyze only: emit {duration, peaks, silences} for the app's "
                        "live cut preview — no transcription, no render")
    p.add_argument("--keep-file", default=None,
                   help="render exactly the segments listed in this JSON file "
                        '({"keep": [[start, end], ...]}, seconds on the original '
                        "timeline) instead of detecting cuts — used by the app's "
                        "review timeline. Skips analysis, transcription, and the model.")
    args = p.parse_args()

    # The Core ML filler backend needs a model — fail fast at the CLI rather than
    # deep in detection after audio extraction.
    if args.filler_backend == "coreml" and not args.filler_model:
        p.error("--filler-backend coreml requires --filler-model")

    # --analyze returns early (before the clean), so a --keep-file passed alongside it
    # would be silently ignored. Fail fast rather than behave ambiguously.
    if args.analyze and args.keep_file:
        p.error("--analyze and --keep-file can't be used together.")

    if args.ndjson:
        _enable_group_cancel()
        def emit(obj):
            print(json.dumps(obj), flush=True)
        user_log = lambda m: emit({"event": "log", "message": m})
        on_progress = lambda f, l="": emit({"event": "progress", "fraction": f, "label": l})
    else:
        def user_log(msg):
            print(f"→ {msg}" if not msg.startswith(("=", "✅")) else f"\n{msg}", flush=True)
        on_progress = None

    # Tee every human status line into the run log, and record the invocation so a
    # log starts with exactly how the engine was called.
    log = logger_from_env(args.log_dir, tag=os.path.basename(args.video))
    # Quote each arg so the logged invocation is copy-paste replayable (paths with
    # spaces stay intact).
    log.info("clean_video invoked: " + " ".join(shlex.quote(a) for a in sys.argv[1:]))

    def on_log(msg):
        log.info(msg)
        user_log(msg)

    # Analyze-only path for the app's live cut preview: no transcription, no render.
    if args.analyze:
        from crisp import analyze
        try:
            buckets = args.waveform if args.waveform > 0 else 240
            data = analyze(args.video, noise=args.noise, buckets=buckets, on_log=on_log, logger=log)
            if args.ndjson:
                emit({"event": "analysis", **data})
            else:
                print(f"duration={data['duration']:.2f}s silences={len(data['silences'])}", flush=True)
        except CleanError as e:
            log.error(f"CleanError (analyze): {e}")
            if args.ndjson:
                emit({"event": "error", "message": str(e)})
            else:
                print(f"ERROR: {e}", flush=True)
            sys.exit(1)
        except Exception as e:
            # Turn an unexpected failure into a structured error + logged traceback,
            # so it never escapes as a raw traceback on stderr (which the app can't
            # parse, and which could flood the pipe).
            log.exception("Unexpected error (analyze)")
            if args.ndjson:
                emit({"event": "error", "message": f"Unexpected error: {e}"})
            else:
                print(f"ERROR: {e}", flush=True)
            sys.exit(1)
        return

    try:
        result = clean_video(args.video, out_path=args.out, model=args.model, pause=args.pause,
                             noise=args.noise, keep_pause=args.keep_pause, min_keep=args.min_keep,
                             studio_sound=args.studio_sound,
                             video_codec=args.video_codec, hardware=args.hardware, quality=args.quality,
                             audio_codec=args.audio_codec, audio_bitrate=args.audio_bitrate,
                             container=args.container, color_depth=args.color_depth,
                             remove_fillers=not args.no_fillers,
                             remove_retakes=not args.no_retakes,
                             retake_sensitivity=args.retake_sensitivity,
                             backup=not args.no_backup, backup_dir=args.backup_dir,
                             out_dir=args.out_dir, split_tracks=args.split,
                             split_audio=args.split_audio, waveform_buckets=args.waveform,
                             keep_file=args.keep_file, captions=args.captions,
                             filler_backend=args.filler_backend, filler_model=args.filler_model,
                             fade_ms=args.fade_ms, crossfade_ms=args.crossfade_ms, snap_ms=args.snap_ms,
                             fps_mode=args.fps_mode, fps=args.fps,
                             export_timeline=args.export_timeline, project_dir=args.project_dir,
                             on_log=on_log, on_progress=on_progress, logger=log)
        if args.ndjson:
            emit({"event": "result", **result})
    except CleanError as e:
        log.error(f"CleanError: {e}")
        if args.ndjson:
            emit({"event": "error", "message": str(e)})
        else:
            print(f"ERROR: {e}", flush=True)
        sys.exit(1)
    except Exception as e:
        # An unexpected (non-CleanError) failure used to escape as a raw traceback —
        # never reaching the app as a structured error. Log the traceback and turn
        # it into one, so the UI shows a real message and the log has the detail.
        log.exception("Unexpected error")
        if args.ndjson:
            emit({"event": "error", "message": f"Unexpected error: {e}"})
            sys.exit(1)
        raise


if __name__ == "__main__":
    main()
