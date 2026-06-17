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
    DEFAULT_AUDIO_BITRATE, DEFAULT_AUDIO_CODEC, DEFAULT_CONTAINER, DEFAULT_KEEP_PAUSE,
    DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB, DEFAULT_QUALITY, DEFAULT_VIDEO_CODEC, MIN_KEEP,
)
from crisp.encode import SUPPORTED_CONTAINERS


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
    p.add_argument("--no-fillers", action="store_true", help="only remove pauses, keep um/uh")
    p.add_argument("--no-backup", action="store_true",
                   help="don't copy the original aside before cutting")
    p.add_argument("--backup-dir", default=None,
                   help="folder to copy the original into (default: an '_originals' folder beside it)")
    p.add_argument("--out", default=None,
                   help="output path (default: <name>_cleaned.<ext> beside input, ext per --container)")
    p.add_argument("--ndjson", action="store_true",
                   help="emit machine-readable progress as one JSON object per line "
                        "(used by the desktop app)")
    args = p.parse_args()

    if args.ndjson:
        _enable_group_cancel()
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
                             noise=args.noise, keep_pause=args.keep_pause, min_keep=args.min_keep,
                             video_codec=args.video_codec, hardware=args.hardware, quality=args.quality,
                             audio_codec=args.audio_codec, audio_bitrate=args.audio_bitrate,
                             container=args.container, remove_fillers=not args.no_fillers,
                             backup=not args.no_backup, backup_dir=args.backup_dir,
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
