"""Benchmark a trained checkpoint on the PodcastFillers test split.

Beyond a single F1, this reports what actually decides whether the model is
Crisp-ready:

  - threshold sweep: precision / recall / F1 across decision thresholds. Crisp
    wants HIGH PRECISION — a false positive cuts real speech, worse than missing
    an "um" — so the operating point is a product decision, not always 0.5.
  - error breakdown: which non-filler sounds (Words/Breath/Laughter/Music/None)
    get misfired as fillers, and Uh-vs-Um recall.
  - speed: chunks/sec and the real-time factor (how many seconds of audio it
    processes per second) — the model's whole selling point over whisper.

    python -m filler_classifier.benchmark --data data/PodcastFillers
"""
from __future__ import annotations

import argparse
import csv
import time
from collections import Counter
from pathlib import Path

import torch

from . import config, features
from .corpora import PF_FILLERS
from .infer import load_model


def _test_examples(root, split):
    """Yield (clip_path, center_sec, binary_label, original_vocab) for a split."""
    root = Path(root)
    clip_dir = root / "audio" / "clip_wav"
    with open(root / "metadata" / "PodcastFillers.csv", newline="") as f:
        for r in csv.DictReader(f):
            if r["clip_split_subset"] != split:
                continue
            path = clip_dir / split / r["clip_name"]
            if not path.exists():
                continue
            vocab = r["label_consolidated_vocab"]
            if vocab in PF_FILLERS:
                center = (float(r["event_start_inclip"]) + float(r["event_end_inclip"])) / 2.0
                yield path, center, 1, vocab
            else:
                center = (float(r["clip_end_inepisode"]) - float(r["clip_start_inepisode"])) / 2.0
                yield path, center, 0, vocab


def _prf(probs, y, thr):
    pred = probs >= thr
    tp = int(((pred == 1) & (y == 1)).sum())
    fp = int(((pred == 1) & (y == 0)).sum())
    fn = int(((pred == 0) & (y == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return prec, rec, f1


def run(root, checkpoint, split):
    model = load_model(checkpoint)

    patches, labels, vocabs = [], [], []
    for path, center, label, vocab in _test_examples(root, split):
        wav = features.load_waveform(str(path))
        patches.append(features.chunk_at(wav, center))
        labels.append(label)
        vocabs.append(vocab)
    if not patches:
        raise SystemExit(f"No examples for split={split!r} under {root!r}.")
    X = torch.stack(patches)
    y = torch.tensor(labels)
    print(f"test examples: {len(X)}  ({int(y.sum())} filler, {int((y == 0).sum())} non-filler)\n")

    # ---- speed (batched forward, warmed up) ----
    with torch.no_grad():
        model(X[:64])                                     # warmup
        t0 = time.perf_counter()
        probs = torch.sigmoid(model(X))
        dt = time.perf_counter() - t0
    chunks_per_sec = len(X) / dt
    realtime = chunks_per_sec * config.CHUNK_HOP_SEC      # audio-seconds processed per wall-second
    print(f"speed: {chunks_per_sec:,.0f} chunks/sec  →  ~{realtime:,.0f}× real-time "
          f"(processes {realtime:,.0f}s of audio per second, CPU)\n")

    # ---- threshold sweep ----
    print("threshold   precision   recall    F1")
    for thr in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9):
        prec, rec, f1 = _prf(probs, y, thr)
        print(f"   {thr:.1f}        {prec:.3f}      {rec:.3f}   {f1:.3f}")

    # ---- error breakdown at 0.5 ----
    pred = probs >= 0.5
    n_by, fp_by = Counter(), Counter()
    for i, v in enumerate(vocabs):
        n_by[v] += 1
        if y[i] == 0 and pred[i] == 1:
            fp_by[v] += 1
    print("\nfalse positives by non-filler sound (thr=0.5) — what it wrongly cuts:")
    for v in sorted(n_by, key=lambda k: -fp_by[k]):
        if v not in PF_FILLERS:
            pct = 100 * fp_by[v] / n_by[v] if n_by[v] else 0
            print(f"  {v:10s} {fp_by[v]:4d}/{n_by[v]:<5d}  ({pct:.1f}% misfired)")

    print("\nrecall by filler type (thr=0.5):")
    for v in ("Uh", "Um"):
        idx = [i for i, vv in enumerate(vocabs) if vv == v]
        rec = sum(int(pred[i]) for i in idx) / len(idx) if idx else 0.0
        print(f"  {v}: {rec:.3f}  ({len(idx)} clips)")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--split", default="test")
    a = p.parse_args()
    run(a.data, a.checkpoint, a.split)


if __name__ == "__main__":
    main()
