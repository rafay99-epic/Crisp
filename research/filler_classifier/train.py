"""Train the filler classifier on hand-labeled clips.

    python -m filler_classifier.train --data data/ --epochs 30

Saves the best-val-F1 checkpoint to checkpoints/filler_cnn.pt.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torch.utils.data import DataLoader, random_split

from .dataset import FillerChunks
from .model import FillerCNN


def run(data_dir, epochs, batch_size, lr, val_frac, out):
    ds = FillerChunks(data_dir)
    if len(ds) == 0:
        raise SystemExit(f"No labeled chunks found in {data_dir!r}. "
                         "Add *.wav + *.fillers.json pairs first (see README).")

    n_val = max(1, int(len(ds) * val_frac))
    n_train = len(ds) - n_val
    train_ds, val_ds = random_split(
        ds, [n_train, n_val], generator=torch.Generator().manual_seed(0))
    train_dl = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_dl = DataLoader(val_ds, batch_size=batch_size)

    model = FillerCNN()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = torch.nn.BCEWithLogitsLoss(pos_weight=ds.pos_weight())

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    best_f1 = -1.0
    for epoch in range(1, epochs + 1):
        model.train()
        for x, y in train_dl:
            opt.zero_grad()
            loss_fn(model(x), y).backward()
            opt.step()

        f1, prec, rec = _evaluate(model, val_dl)
        print(f"epoch {epoch:3d}  val P={prec:.3f} R={rec:.3f} F1={f1:.3f}")
        if f1 > best_f1:
            best_f1 = f1
            torch.save(model.state_dict(), out)
            print(f"  ↳ saved {out} (F1={f1:.3f})")
    print(f"best val F1={best_f1:.3f}")


@torch.no_grad()
def _evaluate(model, dl):
    model.eval()
    tp = fp = fn = 0
    for x, y in dl:
        pred = (torch.sigmoid(model(x)) >= 0.5).float()
        tp += float(((pred == 1) & (y == 1)).sum())
        fp += float(((pred == 1) & (y == 0)).sum())
        fn += float(((pred == 0) & (y == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return f1, prec, rec


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--data", default="data")
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--val-frac", type=float, default=0.2)
    p.add_argument("--out", default="checkpoints/filler_cnn.pt")
    a = p.parse_args()
    run(a.data, a.epochs, a.batch_size, a.lr, a.val_frac, a.out)


if __name__ == "__main__":
    main()
