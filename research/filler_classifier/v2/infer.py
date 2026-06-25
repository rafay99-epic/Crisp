"""Wren v2 inference — any audio/video → removable-filler spans, with an A/B vs v0.0.8.

Runs the fully-convolutional TCN over the WHOLE recording in one pass (no sliding
chunks), thresholds the per-frame P(removable), and merges into spans. This mirrors
what the shipped helper will do, and doubles as the Phase-4 real-data test:

    # how much would each model cut on your footage? (the over-cutting check)
    python -m filler_classifier.v2.infer /path/to/your_video.mp4 --compare

    # just v2's spans (e.g. on a FluencyBank clip), at a chosen operating point:
    python -m filler_classifier.v2.infer clip.wav --threshold 0.9

`--compare` runs the old 0.25s chunk model (v0.0.8) on the same audio so you can see,
side by side, whether v2 cuts *less* (and at better spots). Accepts mp4/mp3/wav/etc.
(anything ffmpeg can read). Run with the torch env (.venv).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

import torch

from .. import config, features
from ..v1.infer import predict_intervals as predict_chunks   # old v0.0.8 path
from ..v1.model import FillerCNN
from .model import WrenSeq

FFMPEG = os.environ.get("CRISP_FFMPEG", "ffmpeg")


def to_waveform(src: str) -> torch.Tensor:
    """Any media file → mono 16 kHz waveform (via ffmpeg → wav → the shared loader)."""
    if src.lower().endswith(".wav"):
        return features.load_waveform(src)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run([FFMPEG, "-y", "-i", src, "-vn", "-ac", "1",
                        "-ar", str(config.SAMPLE_RATE), "-c:a", "pcm_s16le", str(wav)],
                       check=True, capture_output=True)
        return features.load_waveform(str(wav))


def predict_spans(model, waveform, threshold, merge_gap=config.MERGE_GAP_SEC,
                  min_len=config.MIN_FILLER_SEC):
    """Run WrenSeq over the whole recording → merged removable spans [(start, end), …]."""
    mel = features.normalize(features.log_mel(waveform))      # [n_mels, T]
    with torch.no_grad():
        probs = torch.sigmoid(model(mel.unsqueeze(0))).squeeze(0)   # [T] per-frame

    runs, start = [], None
    for i, p in enumerate(probs):
        if p >= threshold:
            start = i if start is None else start
        elif start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, len(probs)))

    secs = [[a * config.FRAME_SEC, b * config.FRAME_SEC] for a, b in runs]
    merged = []
    for s, e in secs:
        if merged and s - merged[-1][1] <= merge_gap:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged if e - s >= min_len]


def summarize(name, spans, duration):
    total = sum(e - s for s, e in spans)
    pct = 100 * total / duration if duration else 0
    mm, ss = divmod(total, 60)
    print(f"  {name:18} {len(spans):4} fillers   {int(mm):d}m{ss:04.1f}s cut   ({pct:.1f}% of audio)")
    return total


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("media", help="audio/video file (mp4/mp3/wav/…)")
    p.add_argument("--model", default="checkpoints/wren_seq.pt")
    p.add_argument("--threshold", type=float, default=0.9, help="operating point (sweep peaked ~0.9)")
    p.add_argument("--compare", action="store_true", help="also run the old v0.0.8 chunk model")
    p.add_argument("--out", default=None, help="write v2 spans JSON here (for rendering later)")
    a = p.parse_args()

    wav = to_waveform(a.media)
    duration = len(wav) / config.SAMPLE_RATE

    seq = WrenSeq()
    seq.load_state_dict(torch.load(a.model, map_location="cpu"))
    seq.eval()
    v2 = predict_spans(seq, wav, a.threshold)

    print(f"\n{Path(a.media).name}  ({duration/60:.1f} min)  threshold={a.threshold}")
    if a.compare and Path("checkpoints/filler_cnn.pt").exists():
        old = FillerCNN()
        old.load_state_dict(torch.load("checkpoints/filler_cnn.pt", map_location="cpu"))
        old.eval()
        summarize("v0.0.8 (chunk)", predict_chunks(old, wav), duration)
    summarize("v2 (context)", v2, duration)

    if a.out:
        Path(a.out).write_text(json.dumps({"fillers": [[round(s, 3), round(e, 3)] for s, e in v2]}))
        print(f"\n  v2 spans → {a.out}")


if __name__ == "__main__":
    main()
