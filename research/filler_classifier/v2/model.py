"""Wren v2 — a tiny dilated TCN over a log-mel sequence → per-frame P(removable).

Where v0.0.8 (`model.FillerCNN`) classified one 0.25s chunk in isolation, this reads a
*sequence* and, for every 10ms frame, decides whether that instant is part of a
**removable** filler — using the multi-second context around it (was there a pause? is
this woven into fluent speech?). That context is the whole point: it's what lets the
model keep natural mid-sentence "hmm"s while still cutting standalone disfluencies.

Design choices:
  • **TCN, not GRU** — stacked *dilated* 1-D convolutions give a multi-second receptive
    field with no recurrent state: trivially parallel, stable to train, and it exports
    to Core ML cleanly (plain convs/BN/ReLU). A GRU would be fiddlier to ship.
  • **Fully convolutional** — symmetric ('same') padding keeps output length == input
    length, so we train on fixed 4s windows but run inference over an entire recording
    in one forward pass. No sliding-chunk machinery, no train/serve seam.
  • **Tiny** (~130k params) — same shippability bar as v0.0.8.

  Receptive field with dilations (1,2,4,8,16), k=3, 2 convs/block:
    1 + 2·(k-1)·Σdil = 1 + 4·31 = 125 frames ≈ 1.25s each side → ~2.5s of context.
"""
from __future__ import annotations

import torch
from torch import nn


class TCNBlock(nn.Module):
    """Residual block of two dilated 'same'-padded convolutions."""

    def __init__(self, ch: int, dilation: int, k: int = 3, p: float = 0.1):
        super().__init__()
        pad = dilation * (k - 1) // 2          # symmetric → preserves length (k odd)
        self.conv1 = nn.Conv1d(ch, ch, k, padding=pad, dilation=dilation)
        self.bn1 = nn.BatchNorm1d(ch)
        self.conv2 = nn.Conv1d(ch, ch, k, padding=pad, dilation=dilation)
        self.bn2 = nn.BatchNorm1d(ch)
        self.drop = nn.Dropout(p)
        self.act = nn.ReLU()

    def forward(self, x):
        y = self.drop(self.act(self.bn1(self.conv1(x))))
        y = self.bn2(self.conv2(y))
        return self.act(x + y)                 # residual


class WrenSeq(nn.Module):
    def __init__(self, n_mels: int = 64, ch: int = 64, dilations=(1, 2, 4, 8, 16)):
        super().__init__()
        self.inp = nn.Conv1d(n_mels, ch, 1)               # mels → channels
        self.blocks = nn.Sequential(*[TCNBlock(ch, d) for d in dilations])
        self.head = nn.Conv1d(ch, 1, 1)                   # → one logit per frame

    def forward(self, x):                                  # x: [B, n_mels, T]
        z = self.blocks(self.inp(x))
        return self.head(z).squeeze(1)                     # [B, T] per-frame logits
