"""Precision / recall / F1 of a trained checkpoint on held-out data.

    # a public-corpus split (chunk-level metric):
    python -m filler_classifier.evaluate --dataset podcastfillers --data data/PodcastFillers --split test

    # your own labeled recordings (interval overlap on the chunk grid):
    python -m filler_classifier.evaluate --dataset folder --data data/val
"""
from __future__ import annotations

import argparse

from torch.utils.data import DataLoader

from . import config, corpora, features
from .dataset import find_pairs
from .infer import load_model, predict_intervals
from .labeling import label_for_time, load_intervals
from .train import evaluate_model


def run_corpus(dataset, data_dir, split, checkpoint, threshold):
    model = load_model(checkpoint)
    ds = corpora.build(dataset, data_dir, (split,))
    dl = DataLoader(ds, batch_size=128)
    f1, prec, rec = evaluate_model(model, dl, threshold=threshold)
    print(f"{dataset}[{split}]  chunks={len(ds)}  P={prec:.3f}  R={rec:.3f}  F1={f1:.3f}")


def run_folder(data_dir, checkpoint, threshold):
    model = load_model(checkpoint)
    tp = fp = fn = clips = 0
    for wav, label in find_pairs(data_dir):
        clips += 1
        gold = load_intervals(label)
        waveform = features.load_waveform(str(wav))
        pred = predict_intervals(model, waveform, threshold=threshold)
        _, centers = features.chunks_from_waveform(waveform)
        for t in centers:
            g, p = label_for_time(t, gold), label_for_time(t, pred)
            tp += int(g == 1 and p == 1)
            fp += int(g == 0 and p == 1)
            fn += int(g == 1 and p == 0)
    if clips == 0:
        raise SystemExit(f"No labeled clips found in {data_dir!r}.")
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    print(f"folder  clips={clips}  P={prec:.3f}  R={rec:.3f}  F1={f1:.3f}  "
          f"(tp={tp} fp={fp} fn={fn})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dataset", choices=["podcastfillers", "sep28k", "folder"],
                   default="podcastfillers")
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--split", default="test", help="corpus split (podcastfillers only)")
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--threshold", type=float, default=config.DEFAULT_THRESHOLD)
    a = p.parse_args()
    if a.dataset == "folder":
        run_folder(a.data, a.checkpoint, a.threshold)
    else:
        run_corpus(a.dataset, a.data, a.split, a.checkpoint, a.threshold)


if __name__ == "__main__":
    main()
