"""Train Wren v2 — the context-aware temporal filler model.

    # one-time: cache mels + build windows (slow, decodes audio once)
    python -m filler_classifier.v2.preprocess --splits train validation
    # then train (watch the per-frame P/R/F1 climb on the validation episodes)
    python -m filler_classifier.v2.train --data data/labels_v2 --epochs 40

Saves the best-val-F1 checkpoint to checkpoints/wren_seq.pt. Metrics are *per-frame*
(at 10 ms): precision = of the frames we flag as removable, how many really are
(↑ precision = less over-cutting); recall = of real removable frames, how many we
catch. F1 balances them.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torch.utils.data import DataLoader

from .. import config
from .dataset import SeqWindows
from .model import WrenSeq


@torch.no_grad()
def evaluate(model, dl, device, threshold=0.5):
    model.eval()
    tp = fp = fn = 0
    for x, y in dl:
        x, y = x.to(device), y.to(device)
        pred = (torch.sigmoid(model(x)) >= threshold).float()
        tp += float(((pred == 1) & (y == 1)).sum())
        fp += float(((pred == 1) & (y == 0)).sum())
        fn += float(((pred == 0) & (y == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
    return f1, prec, rec


def run(data_dir, epochs, batch_size, lr, workers, out):
    data_dir = Path(data_dir)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    train_ds = SeqWindows(data_dir / "windows_train.jsonl", data_dir / "mels")
    val_ds = SeqWindows(data_dir / "windows_validation.jsonl", data_dir / "mels")
    pos_weight = train_ds.pos_weight().to(device)
    print(f"device={device}  train={len(train_ds)} windows  val={len(val_ds)} windows  "
          f"pos_weight={pos_weight.item():.1f}")

    train_dl = DataLoader(train_ds, batch_size=batch_size, shuffle=True, num_workers=workers)
    val_dl = DataLoader(val_ds, batch_size=batch_size, num_workers=workers)

    torch.manual_seed(0)
    model = WrenSeq().to(device)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"WrenSeq: {n_params:,} params")
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = torch.nn.BCEWithLogitsLoss(pos_weight=pos_weight)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    best_f1 = -1.0
    for epoch in range(1, epochs + 1):
        model.train()
        running = 0.0
        for x, y in train_dl:
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            running += loss.item()
        f1, prec, rec = evaluate(model, val_dl, device)
        print(f"epoch {epoch:3d}  loss={running/len(train_dl):.4f}  "
              f"val P={prec:.3f} R={rec:.3f} F1={f1:.3f}"
              + ("   ↳ best" if f1 > best_f1 else ""))
        if f1 > best_f1:
            best_f1 = f1
            torch.save(model.state_dict(), out)
    print(f"best val F1={best_f1:.3f}  → {out}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/labels_v2", help="dir with windows_*.jsonl + mels/")
    p.add_argument("--epochs", type=int, default=40)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--out", default="checkpoints/wren_seq.pt")
    a = p.parse_args()
    run(a.data, a.epochs, a.batch_size, a.lr, a.workers, a.out)


if __name__ == "__main__":
    main()
