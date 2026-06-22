"""A small CNN over a log-mel chunk → one filler logit.

Deliberately tiny (~75k params): the task is narrow, the hand-labeled data is
limited, and the model must export cleanly to Core ML and run in real time.
"""
from __future__ import annotations

import torch
from torch import nn


class FillerCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, 3, padding=1), nn.BatchNorm2d(16), nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(16, 32, 3, padding=1), nn.BatchNorm2d(32), nn.ReLU(),
            nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1), nn.BatchNorm2d(64), nn.ReLU(),
            nn.AdaptiveAvgPool2d(1),
        )
        self.head = nn.Linear(64, 1)

    def forward(self, x):                  # x: [B, 1, n_mels, CHUNK_FRAMES]
        z = self.features(x).flatten(1)    # [B, 64]
        return self.head(z).squeeze(1)     # [B] raw logits
