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
import sys
from pathlib import Path

# Ensure the sibling `crisp` package is importable however this script is invoked.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from crisp import CleanError, clean_video
from crisp.config import (
    DEFAULT_KEEP_PAUSE, DEFAULT_MAX_PAUSE, DEFAULT_MODEL, DEFAULT_NOISE_DB,
)


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
