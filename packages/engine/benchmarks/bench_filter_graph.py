#!/usr/bin/env python3
"""Benchmark the render path against segment count.

ffmpeg's filter-graph scheduling is quadratic in the number of live filters, so
the old single-pass trim graph (~4 filters per kept segment) blew up on many-cut
renders; crisp.edit batches past _BATCH_THRESHOLD segments instead. This prints
both paths side by side so a future ffmpeg upgrade (or graph change) can be
re-measured in one command:

    python3 benchmarks/bench_filter_graph.py            # from packages/engine
    python3 benchmarks/bench_filter_graph.py 1200       # add a segment count

Needs ffmpeg on PATH (or CRISP_FFMPEG). Generates its own 60s test clip in a
temp dir; nothing is written to the repo. Reference numbers (M-series Mac,
ffmpeg 8.1.1, 60s 320x240 clip, libx264 ultrafast):

    n=150   single-pass   8.3s     batched  1.6s
    n=600   single-pass 101.6s     batched  3.8s
"""

import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import crisp.edit as edit  # noqa: E402


def make_clip(path):
    subprocess.run(
        [edit.ffmpeg_bin(), "-y", "-v", "error",
         "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30:d=60",
         "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=60",
         "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", str(path)],
        check=True)


def keep_list(n, dur=60.0):
    seg = dur / n
    return [(round(i * seg, 4), round(i * seg + seg * 0.6, 4)) for i in range(n)]


def timed_render(src, keep, out, batched):
    saved = edit._BATCH_THRESHOLD
    edit._BATCH_THRESHOLD = 64 if batched else 10**9
    try:
        t0 = time.time()
        edit.render(src, keep, out, lambda m: None, lambda f, label="": None,
                    video_opts=["-c:v", "libx264", "-preset", "ultrafast"],
                    audio_opts=["-c:a", "aac"], fade=0.010)
        return time.time() - t0
    finally:
        edit._BATCH_THRESHOLD = saved


def main():
    counts = [int(a) for a in sys.argv[1:]] or [50, 150, 300, 600]
    with tempfile.TemporaryDirectory(prefix="crisp-bench-") as tmp:
        src = Path(tmp) / "clip.mp4"
        make_clip(src)
        print(f"{'segments':>8}  {'single-pass':>12}  {'batched':>8}")
        for n in counts:
            keep = keep_list(n)
            flat = timed_render(src, keep, Path(tmp) / "flat.mp4", batched=False)
            bat = timed_render(src, keep, Path(tmp) / "bat.mp4", batched=True)
            print(f"{n:>8}  {flat:>11.2f}s  {bat:>7.2f}s", flush=True)


if __name__ == "__main__":
    main()
