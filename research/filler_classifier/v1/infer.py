"""Reference inference: wav → filler intervals.

This mirrors what the shipped Core ML backend will do, so it doubles as the
parity check: the exported .mlpackage must produce the same intervals as this
script from the same audio.
"""
from __future__ import annotations

import argparse
import json

import torch

from .. import config, features
from .model import FillerCNN


def predict_intervals(model, waveform, threshold=config.DEFAULT_THRESHOLD,
                      merge_gap=config.MERGE_GAP_SEC, min_len=config.MIN_FILLER_SEC):
    """Run the model over a waveform → merged filler intervals [(start, end), …]."""
    patches, centers = features.chunks_from_waveform(waveform)
    if len(centers) == 0:
        return []
    with torch.no_grad():
        probs = torch.sigmoid(model(patches))

    # Group consecutive filler chunks into raw runs.
    half = config.CHUNK_SEC / 2.0
    runs, cur = [], None
    for i, t in enumerate(centers):
        if probs[i] >= threshold:
            if cur is None:
                cur = [t - half, t + half]
            else:
                cur[1] = t + half
        elif cur is not None:
            runs.append(cur)
            cur = None
    if cur is not None:
        runs.append(cur)

    # Bridge small gaps, then drop too-short fillers.
    merged = []
    for run in runs:
        if merged and run[0] - merged[-1][1] <= merge_gap:
            merged[-1][1] = run[1]
        else:
            merged.append(run)
    return [(a, b) for a, b in merged if b - a >= min_len]


def load_model(checkpoint):
    model = FillerCNN()
    model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    model.eval()
    return model


def main():
    p = argparse.ArgumentParser()
    p.add_argument("audio")
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--threshold", type=float, default=config.DEFAULT_THRESHOLD)
    a = p.parse_args()
    model = load_model(a.checkpoint)
    waveform = features.load_waveform(a.audio)
    intervals = predict_intervals(model, waveform, threshold=a.threshold)
    rounded = [[round(s, 3), round(e, 3)] for s, e in intervals]   # round only for display
    print(json.dumps({"fillers": rounded}, indent=2))


if __name__ == "__main__":
    main()
