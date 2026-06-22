"""Machine-readable evaluation report (JSON) for the FillerBench UI.

Emits everything the SwiftUI dashboard renders: dataset summary, inference speed,
a precision/recall/F1 threshold sweep, the best-F1 threshold, false positives
broken down by non-filler sound, and per-filler recall. Same numbers as
`benchmark`, but as a single JSON object on stdout so Swift can render them
natively instead of parsing console text.

    python -m filler_classifier.v1.report --data data/PodcastFillers --split test
"""
from __future__ import annotations

import argparse
import json
import time
from collections import Counter

import torch

from .. import config, features
from .benchmark import _prf, _test_examples
from .corpora import PF_FILLERS
from .infer import load_model


def build_report(root, checkpoint, split, limit=0):
    model = load_model(checkpoint)

    patches, labels, vocabs = [], [], []
    for i, (path, center, label, vocab) in enumerate(_test_examples(root, split)):
        if limit and i >= limit:
            break
        patches.append(features.chunk_at(features.load_waveform(str(path)), center))
        labels.append(label)
        vocabs.append(vocab)
    if not patches:
        raise SystemExit(f"No examples for split={split!r} under {root!r}.")
    X = torch.stack(patches)
    y = torch.tensor(labels)

    with torch.no_grad():
        model(X[:64])                                   # warmup
        t0 = time.perf_counter()
        probs = torch.sigmoid(model(X))
        dt = time.perf_counter() - t0
    chunks_per_sec = len(X) / dt

    sweep = []
    for thr in [round(0.1 * k, 1) for k in range(1, 10)]:
        prec, rec, f1 = _prf(probs, y, thr)
        sweep.append({"threshold": thr, "precision": prec, "recall": rec, "f1": f1})
    best = max(sweep, key=lambda s: s["f1"])

    pred = probs >= 0.5
    n_by, fp_by = Counter(), Counter()
    for i, v in enumerate(vocabs):
        n_by[v] += 1
        if y[i] == 0 and pred[i] == 1:
            fp_by[v] += 1
    fp_by_class = [
        {"label": v, "fp": fp_by[v], "total": n_by[v],
         "pct": (100 * fp_by[v] / n_by[v] if n_by[v] else 0.0)}
        for v in sorted(n_by, key=lambda k: -fp_by[k]) if v not in PF_FILLERS
    ]

    recall_by_filler = []
    for v in ("Uh", "Um"):
        idx = [i for i, vv in enumerate(vocabs) if vv == v]
        rec = sum(int(pred[i]) for i in idx) / len(idx) if idx else 0.0
        recall_by_filler.append({"label": v, "recall": rec, "n": len(idx)})

    return {
        "dataset": "podcastfillers",
        "split": split,
        "checkpoint": checkpoint,
        "n_examples": len(X),
        "n_filler": int(y.sum()),
        "n_nonfiller": int((y == 0).sum()),
        "speed": {"chunks_per_sec": chunks_per_sec,
                  "realtime_factor": chunks_per_sec * config.CHUNK_HOP_SEC},
        "best_f1_threshold": best,
        "sweep": sweep,
        "false_positives_by_class": fp_by_class,
        "recall_by_filler": recall_by_filler,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--split", default="test")
    p.add_argument("--limit", type=int, default=0, help="cap examples (for a quick run)")
    a = p.parse_args()
    print(json.dumps(build_report(a.data, a.checkpoint, a.split, a.limit)))


if __name__ == "__main__":
    main()
