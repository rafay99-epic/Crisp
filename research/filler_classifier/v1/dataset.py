"""Torch Dataset: chunks of log-mel with filler/non-filler targets.

Scans a directory for `*.wav` files each paired with a `*.fillers.json` label
file (see labeling.py). Every chunk becomes one training example, labeled by
whether its center time lands inside a filler interval.
"""
from __future__ import annotations

from pathlib import Path

import torch
from torch.utils.data import Dataset

from .. import features
from .labeling import label_for_time, load_intervals


def find_pairs(data_dir):
    """Yield (wav_path, label_path) for every labeled clip directly in data_dir.

    Subdirectories (e.g. data/val) are not recursed — point --data at them
    explicitly so train/val never leak into each other.
    """
    data_dir = Path(data_dir)
    for wav in sorted(data_dir.glob("*.wav")):
        label = wav.with_suffix(".fillers.json")
        if label.exists():
            yield wav, label


class FillerChunks(Dataset):
    def __init__(self, data_dir):
        self.patches = []
        labels = []
        for wav, label in find_pairs(data_dir):
            intervals = load_intervals(label)
            waveform = features.load_waveform(str(wav))
            patches, centers = features.chunks_from_waveform(waveform)
            for i, t in enumerate(centers):
                self.patches.append(patches[i])
                labels.append(label_for_time(t, intervals))
        self.labels = torch.tensor(labels, dtype=torch.float32)

    def __len__(self):
        return len(self.patches)

    def __getitem__(self, i):
        return self.patches[i], self.labels[i]

    def pos_weight(self):
        """BCE pos_weight to offset class imbalance (fillers are rare)."""
        pos = float(self.labels.sum())
        neg = float(len(self.labels)) - pos
        if pos == 0 or neg == 0:        # single-class set: neg/pos would be 0 (kills the gradient)
            return torch.tensor(1.0)
        return torch.tensor(neg / pos)
