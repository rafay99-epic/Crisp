"""Frame-level precision/recall against gold labels on held-out clips.

    python -m filler_classifier.evaluate --data data/val --checkpoint checkpoints/filler_cnn.pt

Compares predicted filler intervals to the hand-labeled ones, sampled on the
chunk grid — the granularity at which cuts actually happen.
"""
from __future__ import annotations

import argparse

from . import config, features
from .dataset import find_pairs
from .infer import load_model, predict_intervals
from .labeling import label_for_time, load_intervals


def run(data_dir, checkpoint, threshold):
    model = load_model(checkpoint)
    tp = fp = fn = 0
    clips = 0
    for wav, label in find_pairs(data_dir):
        clips += 1
        gold = load_intervals(label)
        waveform = features.load_waveform(str(wav))
        pred = predict_intervals(model, waveform, threshold=threshold)
        _, centers = features.chunks_from_waveform(waveform)
        for t in centers:
            g = label_for_time(t, gold)
            p = label_for_time(t, pred)
            tp += int(g == 1 and p == 1)
            fp += int(g == 0 and p == 1)
            fn += int(g == 1 and p == 0)

    if clips == 0:
        raise SystemExit(f"No labeled clips found in {data_dir!r}.")
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    print(f"clips={clips}  P={prec:.3f}  R={rec:.3f}  F1={f1:.3f}  "
          f"(tp={tp} fp={fp} fn={fn})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", default="data/val")
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--threshold", type=float, default=config.DEFAULT_THRESHOLD)
    a = p.parse_args()
    run(a.data, a.checkpoint, a.threshold)


if __name__ == "__main__":
    main()
