"""Wren v2 — serve (mel window, per-frame label) pairs from the preprocessed cache.

Reads the window index from `preprocess_v2` and memory-maps each episode's cached
log-mel, so __getitem__ is just a slice + building the 0/1 label vector. The label is
1 only on frames inside a removable-filler span; everything else (speech, silence,
*natural* fillers) is 0 — that's how the model learns to keep natural fillers.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset

from .. import config


class SeqWindows(Dataset):
    def __init__(self, index_path: str, mel_dir: str):
        self.windows = [json.loads(line) for line in open(index_path)]
        self.mel_dir = Path(mel_dir)
        self._mels: dict[str, np.memmap] = {}

    def __len__(self):
        return len(self.windows)

    def _mel(self, episode: str) -> np.memmap:
        m = self._mels.get(episode)
        if m is None:
            m = np.load(self.mel_dir / f"{episode}.npy", mmap_mode="r")
            self._mels[episode] = m
        return m

    def __getitem__(self, i):
        w = self.windows[i]
        W = config.WINDOW_FRAMES
        mel = self._mel(w["episode"])               # [n_mels, T_full]
        f0 = w["start_frame"]
        x = np.asarray(mel[:, f0:f0 + W], dtype=np.float32)
        if x.shape[1] < W:                          # right-pad short tail windows
            x = np.pad(x, ((0, 0), (0, W - x.shape[1])))

        y = np.zeros(W, dtype=np.float32)
        for a, b in w["spans"]:
            y[max(0, a - f0):max(0, b - f0)] = 1.0
        return torch.from_numpy(x), torch.from_numpy(y)

    def pos_weight(self) -> torch.Tensor:
        """Per-frame BCE pos_weight: removable frames are rare even in positive windows."""
        pos = sum(b - a for w in self.windows for a, b in w["spans"])
        total = len(self.windows) * config.WINDOW_FRAMES
        neg = total - pos
        return torch.tensor(neg / pos) if pos else torch.tensor(1.0)
