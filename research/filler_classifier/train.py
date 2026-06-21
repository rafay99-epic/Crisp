"""Train the filler classifier.

    # public corpus (default) — uses PodcastFillers' own train/validation splits:
    python -m filler_classifier.train --dataset podcastfillers --data data/PodcastFillers

    # your own hand-labeled recordings (*.wav + *.fillers.json):
    python -m filler_classifier.train --dataset folder --data data/

Saves the best-val-F1 checkpoint to checkpoints/filler_cnn.pt.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torch.utils.data import DataLoader, random_split

from . import corpora
from .dataset import FillerChunks
from .model import FillerCNN


def _load(dataset, data_dir, val_frac):
    """Return (train_ds, val_ds, pos_weight) for the chosen dataset.

    PodcastFillers has built-in splits, so we use them directly. The folder and
    SEP-28k datasets have no split, so we carve a deterministic val slice off.
    """
    if dataset == "podcastfillers":
        train_ds = corpora.podcastfillers(data_dir, ("train",))
        val_ds = corpora.podcastfillers(data_dir, ("validation",))
        return train_ds, val_ds, train_ds.pos_weight()

    if not 0.0 < val_frac < 1.0:
        raise SystemExit(f"--val-frac must be in (0, 1), got {val_frac}.")
    full = corpora.sep28k(data_dir) if dataset == "sep28k" else FillerChunks(data_dir)
    if len(full) < 2:
        raise SystemExit(f"Need >=2 labeled examples for --dataset {dataset} in {data_dir!r}, "
                         f"found {len(full)}.")
    n_val = min(len(full) - 1, max(1, int(len(full) * val_frac)))   # keep both splits non-empty
    train_ds, val_ds = random_split(
        full, [len(full) - n_val, n_val], generator=torch.Generator().manual_seed(0))
    return train_ds, val_ds, full.pos_weight()


def run(dataset, data_dir, epochs, batch_size, lr, val_frac, workers, out):
    torch.manual_seed(0)                          # reproducible weight init + shuffling
    train_ds, val_ds, pos_weight = _load(dataset, data_dir, val_frac)
    print(f"{dataset}: {len(train_ds)} train chunks, {len(val_ds)} val chunks, "
          f"pos_weight={pos_weight.item():.2f}")

    train_dl = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=workers)
    val_dl = DataLoader(val_ds, batch_size=batch_size, num_workers=workers)

    model = FillerCNN()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = torch.nn.BCEWithLogitsLoss(pos_weight=pos_weight)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    best_f1 = -1.0
    for epoch in range(1, epochs + 1):
        model.train()
        for x, y in train_dl:
            opt.zero_grad()
            loss_fn(model(x), y).backward()
            opt.step()

        f1, prec, rec = evaluate_model(model, val_dl)
        print(f"epoch {epoch:3d}  val P={prec:.3f} R={rec:.3f} F1={f1:.3f}")
        if f1 > best_f1:
            best_f1 = f1
            torch.save(model.state_dict(), out)
            print(f"  ↳ saved {out} (F1={f1:.3f})")
    print(f"best val F1={best_f1:.3f}")


@torch.no_grad()
def evaluate_model(model, dl, threshold=0.5):
    """Chunk-level precision / recall / F1 over a DataLoader."""
    model.eval()
    tp = fp = fn = 0
    for x, y in dl:
        pred = (torch.sigmoid(model(x)) >= threshold).float()
        tp += float(((pred == 1) & (y == 1)).sum())
        fp += float(((pred == 1) & (y == 0)).sum())
        fn += float(((pred == 0) & (y == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return f1, prec, rec


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dataset", choices=["podcastfillers", "sep28k", "folder"],
                   default="podcastfillers")
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--val-frac", type=float, default=0.2,
                   help="val fraction for folder/sep28k (PodcastFillers uses its own splits)")
    p.add_argument("--workers", type=int, default=4, help="DataLoader workers (0 = main thread)")
    p.add_argument("--out", default="checkpoints/filler_cnn.pt")
    a = p.parse_args()
    run(a.dataset, a.data, a.epochs, a.batch_size, a.lr, a.val_frac, a.workers, a.out)


if __name__ == "__main__":
    main()
