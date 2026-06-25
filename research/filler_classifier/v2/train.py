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
from torch.nn import functional as F
from torch.utils.data import ConcatDataset, DataLoader

from .. import config
from .dataset import SeqWindows
from .model import WrenSeq


class FocalLoss(torch.nn.Module):
    """Per-frame focal loss with logits. Keeps the proven `pos_weight` class balancing
    and adds a (1-pt)**gamma modulation so training focuses on the HARD frames —
    boundary fillers, music, noise — instead of the easy speech/clear-filler majority
    (the v3 failure modes). gamma=0 reduces to weighted BCE."""

    def __init__(self, pos_weight=None, gamma=2.0):
        super().__init__()
        if gamma < 0:                       # (1-pt)**gamma explodes as pt→1 → NaN training
            raise ValueError(f"FocalLoss gamma must be >= 0, got {gamma}")
        self.pos_weight = pos_weight
        self.gamma = gamma

    def forward(self, logits, targets):
        bce = F.binary_cross_entropy_with_logits(logits, targets, reduction="none")
        pt = torch.exp(-bce)                                # model confidence on the true class
        loss = (1 - pt) ** self.gamma * bce                 # down-weight easy frames
        if self.pos_weight is not None:                     # still up-weight rare removable frames
            loss = loss * torch.where(targets > 0.5, self.pos_weight, torch.ones_like(targets))
        return loss.mean()


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


def _raise_fd_limit():
    """Memmapped mels (esp. one-.npy-per-window hard negatives) open many files;
    macOS defaults to a 256 soft fd limit, which DataLoader workers blow past. Raise
    the soft limit toward the hard cap so the cache (now LRU-bounded too) has headroom."""
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        target = 8192 if hard == resource.RLIM_INFINITY else min(8192, hard)
        if target > soft:
            resource.setrlimit(resource.RLIMIT_NOFILE, (target, hard))
    except (ImportError, ValueError, OSError):
        pass


def run(data_dir, epochs, batch_size, lr, workers, out, hard_neg=None,
        spec_augment=False, focal=False, focal_gamma=2.0, cosine=False):
    _raise_fd_limit()
    data_dir = Path(data_dir)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    # SpecAugment on the training split only — never on validation.
    train_ds = SeqWindows(data_dir / "windows_train.jsonl", data_dir / "mels", augment=spec_augment)
    val_ds = SeqWindows(data_dir / "windows_validation.jsonl", data_dir / "mels")

    # Optionally mix in all-negative hard-negative windows (SEP-28k music/noise/non-filler)
    # so the model learns what NOT to cut. They add only negatives → pos_weight rises.
    sources = [train_ds]
    if hard_neg:
        hn = SeqWindows(Path(hard_neg) / "windows.jsonl", Path(hard_neg) / "mels", augment=spec_augment)
        sources.append(hn)
        print(f"+ {len(hn)} hard-negative windows from {hard_neg}")
    full_train = ConcatDataset(sources) if len(sources) > 1 else train_ds

    pos = neg = 0
    for ds in sources:
        p = sum(b - a for w in ds.windows for a, b in w["spans"])
        pos += p
        neg += len(ds.windows) * config.WINDOW_FRAMES - p
    pos_weight = torch.tensor(neg / pos if pos else 1.0).to(device)
    print(f"device={device}  train={len(full_train)} windows  val={len(val_ds)} windows  "
          f"pos_weight={pos_weight.item():.1f}")

    train_dl = DataLoader(full_train, batch_size=batch_size, shuffle=True, num_workers=workers)
    val_dl = DataLoader(val_ds, batch_size=batch_size, num_workers=workers)

    torch.manual_seed(0)
    model = WrenSeq().to(device)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"WrenSeq: {n_params:,} params")
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = (FocalLoss(pos_weight=pos_weight, gamma=focal_gamma) if focal
               else torch.nn.BCEWithLogitsLoss(pos_weight=pos_weight))
    sched = (torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs, eta_min=1e-6)
             if cosine else None)
    active = [n for n, on in (("spec-augment", spec_augment),
                              (f"focal(γ={focal_gamma})", focal), ("cosine-lr", cosine)) if on]
    print(f"loss={'focal' if focal else 'BCE'}  techniques: {', '.join(active) or 'none (baseline)'}")

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
        if sched:
            sched.step()
        f1, prec, rec = evaluate(model, val_dl, device)
        print(f"epoch {epoch:3d}  loss={running/len(train_dl):.4f}  "
              f"val P={prec:.3f} R={rec:.3f} F1={f1:.3f}"
              + ("   ↳ best" if f1 > best_f1 else ""))
        if f1 > best_f1:
            best_f1 = f1
            torch.save(model.state_dict(), out)
    print(f"best val F1={best_f1:.3f}  → {out}")


def _non_negative_float(v: str) -> float:
    x = float(v)
    if x < 0:
        raise argparse.ArgumentTypeError(f"must be >= 0, got {x}")
    return x


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/labels_v2", help="dir with windows_*.jsonl + mels/")
    p.add_argument("--epochs", type=int, default=40)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--out", default="checkpoints/wren_seq.pt")
    p.add_argument("--hard-neg", default=None,
                   help="dir with hard-negative windows (e.g. data/hardneg) to mix in")
    # Tier-A training improvements (default off so the current behavior stays the
    # baseline for A/B; the v0.0.11 run turns them on).
    p.add_argument("--spec-augment", action="store_true",
                   help="SpecAugment (freq+time masking) on the training split")
    p.add_argument("--focal", action="store_true",
                   help="focal loss instead of BCE — focuses on hard frames (music/boundary)")
    p.add_argument("--focal-gamma", type=_non_negative_float, default=2.0,
                   help="focal loss gamma >= 0 (with --focal)")
    p.add_argument("--cosine", action="store_true", help="cosine-annealing LR schedule")
    a = p.parse_args()
    run(a.data, a.epochs, a.batch_size, a.lr, a.workers, a.out, a.hard_neg,
        spec_augment=a.spec_augment, focal=a.focal, focal_gamma=a.focal_gamma, cosine=a.cosine)


if __name__ == "__main__":
    main()
