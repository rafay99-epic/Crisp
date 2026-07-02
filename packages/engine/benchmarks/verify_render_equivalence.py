#!/usr/bin/env python3
"""Prove the batched many-cuts render is equivalent to the single-pass graph.

Renders the same cut lists through both paths with LOSSLESS codecs (FFV1 video +
PCM audio) so any divergence is the graph's fault, not the encoder's, then checks:

  1. VIDEO — the decoded frame sequence must be bit-identical (stream md5).
  2. AUDIO — sample-identical within every inter-window region, allowing only a
     bounded (<= one source-audio frame, ~21 ms) constant placement offset of the
     silence at faded-to-zero cut boundaries where windows meet. The offset must
     NOT grow across the file (that would be accumulating A/V drift).

Two cases: segments from t=0 with regular spacing, and mid-file irregular
segments (the shapes that historically flushed out seek/timestamp bugs).

    python3 benchmarks/verify_render_equivalence.py     # from packages/engine

Needs ffmpeg on PATH (or CRISP_FFMPEG). Takes a couple of minutes; prints
PASS/FAIL per check and exits nonzero on failure.
"""

import array
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import crisp.edit as edit  # noqa: E402

SR = 48000
MAX_SHIFT = 1024  # samples; one 1024-sample source-audio frame ≈ 21 ms


def make_clip(path):
    subprocess.run(
        [edit.ffmpeg_bin(), "-y", "-v", "error",
         "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30:d=60",
         "-f", "lavfi", "-i", f"sine=frequency=440:sample_rate={SR}:duration=60",
         "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", str(path)],
        check=True)


def render(src, keep, out, batched):
    saved = edit._BATCH_THRESHOLD
    edit._BATCH_THRESHOLD = 64 if batched else 10**9
    try:
        edit.render(src, keep, out, lambda m: None, lambda f, label="": None,
                    video_opts=["-c:v", "ffv1"], audio_opts=["-c:a", "pcm_s24le"],
                    fade=0.010)
    finally:
        edit._BATCH_THRESHOLD = saved


def video_hash(path):
    r = subprocess.run([edit.ffmpeg_bin(), "-v", "error", "-i", str(path), "-map", "0:v",
                        "-f", "streamhash", "-hash", "md5", "-"],
                       capture_output=True, text=True, check=True)
    return r.stdout.strip()


def audio_samples(path):
    raw = str(path) + ".raw"
    subprocess.run([edit.ffmpeg_bin(), "-y", "-v", "error", "-i", str(path), "-map", "0:a",
                    "-c:a", "pcm_s32le", "-f", "s32le", raw], check=True)
    out = array.array("i")
    out.frombytes(Path(raw).read_bytes())
    return out


def region_shift(a, b, lo, hi):
    """Alignment of b against a inside [lo, hi): search around the loudest spot
    (silence matches any shift, so anchor where there's signal). Returns
    (shift, mismatches_at_that_shift_across_the_region)."""
    step = 2000
    anchor = max(range(lo, hi - step, step),
                 key=lambda i: sum(abs(a[j]) for j in range(i, i + 200)))
    best = None
    for shift in range(-2 * MAX_SHIFT, 2 * MAX_SHIFT + 1):
        if anchor + shift < 0 or anchor + step + shift > len(b):
            continue
        err = sum(a[i] != b[i + shift] for i in range(anchor, anchor + step))
        if best is None or err < best[1]:
            best = (shift, err)
            if err == 0:
                break
    shift = best[0]
    mism = sum(a[i] != b[i + shift] for i in range(lo, min(hi, len(b) - shift)))
    return shift, mism


def check_case(name, src, keep, tmp):
    flat, bat = Path(tmp) / f"{name}_flat.mkv", Path(tmp) / f"{name}_batch.mkv"
    render(src, keep, flat, batched=False)
    render(src, keep, bat, batched=True)

    ok = True
    same_video = video_hash(flat) == video_hash(bat)
    print(f"  video bit-identical: {'PASS' if same_video else 'FAIL'}")
    ok &= same_video

    a, b = audio_samples(flat), audio_samples(bat)
    joins, cum = [], 0.0
    for i, (s, e) in enumerate(keep):
        cum += e - s
        if (i + 1) % edit._BATCH_SIZE == 0:
            joins.append(cum)
    bounds = [0.0] + joins + [min(len(a), len(b)) / SR - 0.05]
    shifts = []
    # Exclude 0.3s around each join from the exact-match requirement: aresample
    # smooths the join's (bounded, ≤ MAX_SHIFT) timing correction over ~0.25s of
    # soft compensation rather than hard-dropping samples — measured to be strictly
    # local to the seam. Everything between seams must be bit-exact at one shift.
    for r in range(len(bounds) - 1):
        lo, hi = int((bounds[r] + 0.3) * SR), int((bounds[r + 1] - 0.06) * SR)
        if hi - lo < SR // 2:
            continue
        shift, mism = region_shift(a, b, lo, hi)
        shifts.append(shift)
        status = mism == 0 and abs(shift) <= MAX_SHIFT
        print(f"  audio region {r}: shift {shift:+d} samples "
              f"({shift / SR * 1000:+.1f} ms), mismatched {mism} "
              f"[{'PASS' if status else 'FAIL'}]")
        ok &= status
    growing = any(abs(shifts[i + 1]) > abs(shifts[i]) + MAX_SHIFT
                  for i in range(len(shifts) - 1))
    print(f"  no accumulating drift: {'PASS' if not growing else 'FAIL'}")
    ok &= not growing
    return ok


def main():
    with tempfile.TemporaryDirectory(prefix="crisp-verify-") as tmp:
        src = Path(tmp) / "clip.mp4"
        make_clip(src)

        n = 90
        seg = 60.0 / n
        regular = [(round(i * seg, 4), round(i * seg + seg * 0.6, 4)) for i in range(n)]

        irregular, t = [], 7.13
        for i in range(130):
            dur = 0.19 + (i % 7) * 0.031
            irregular.append((round(t, 4), round(t + dur, 4)))
            t += dur + 0.17
            if t > 58:
                break

        ok = True
        print("case 1: 90 regular segments from t=0")
        ok &= check_case("c1", src, regular, tmp)
        print(f"case 2: {len(irregular)} irregular segments, mid-file")
        ok &= check_case("c2", src, irregular, tmp)

        # case 3: the production flag shape — HEVC with the QuickTime hvc1 tag,
        # which the NUT intermediates must not receive (they reject stream tags;
        # this exact combination broke the first real-footage render).
        print("case 3: batched render with production HEVC opts (-tag:v hvc1)")
        try:
            edit._BATCH_THRESHOLD = 64
            edit.render(src, regular, Path(tmp) / "c3.mov",
                        lambda m: None, lambda f, label="": None,
                        video_opts=["-c:v", "libx265", "-preset", "ultrafast",
                                    "-crf", "28", "-tag:v", "hvc1",
                                    "-pix_fmt", "yuv420p"],
                        audio_opts=["-c:a", "aac", "-b:a", "192k"], fade=0.010)
            print("  hevc+hvc1 batched render: PASS")
        except Exception as e:  # noqa: BLE001 — report, don't crash the verifier
            print(f"  hevc+hvc1 batched render: FAIL ({e})")
            ok = False

        print("\nOVERALL:", "PASS" if ok else "FAIL")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
