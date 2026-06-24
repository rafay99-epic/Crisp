"""Wren v2 — serve (mel window, per-frame label) pairs from the preprocessed cache.

Reads the window index from `preprocess_v2` and memory-maps each episode's cached
log-mel, so __getitem__ is just a slice + building the 0/1 label vector. The label is
1 only on frames inside a removable-filler span; everything else (speech, silence,
*natural* fillers) is 0 — that's how the model learns to keep natural fillers.
"""
from __future__ import annotations

import json
from collections import OrderedDict
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import Dataset

from .. import config


# SpecAugment defaults (masks applied to the normalized log-mel during training).
# Masking to 0 is correct because the cached mels are mean-normalized (≈0 mean).
FREQ_MASK_PARAM = 15      # max height of a frequency band to zero (of n_mels=64)
TIME_MASK_PARAM = 35      # max width of a time band to zero (of WINDOW_FRAMES)
FREQ_MASKS = 2            # number of frequency masks per window
TIME_MASKS = 2            # number of time masks per window


class SeqWindows(Dataset):
    # Bound the open memmaps. Hard-negative sets cache one .npy per window (thousands
    # of files); without a cap each worker opens an fd per unique file and hits the OS
    # limit ("Too many open files"). An LRU keeps the hot episodes mapped and closes
    # the rest. Comfortably holds the ~66 PodcastFillers episodes without thrashing.
    _MEL_CACHE_CAP = 256

    def __init__(self, index_path: str, mel_dir: str, augment: bool = False):
        with open(index_path) as f:
            self.windows = [json.loads(line) for line in f]
        self.mel_dir = Path(mel_dir)
        self.augment = augment              # SpecAugment — train split only, never val
        self._mels: "OrderedDict[str, np.memmap]" = OrderedDict()

    def __len__(self):
        return len(self.windows)

    def _spec_augment(self, x: np.ndarray) -> np.ndarray:
        """In-place SpecAugment: zero a few random frequency bands + time bands. `x` is
        a fresh float32 copy (the cached mel is float16), so this never touches the cache.
        Mask sizes are random in [0, *_PARAM], so some masks are no-ops — that's intended."""
        n_mels, w = x.shape
        for _ in range(FREQ_MASKS):
            f = np.random.randint(0, FREQ_MASK_PARAM + 1)
            if f and n_mels > f:
                f0 = np.random.randint(0, n_mels - f)
                x[f0:f0 + f, :] = 0.0
        for _ in range(TIME_MASKS):
            t = np.random.randint(0, TIME_MASK_PARAM + 1)
            if t and w > t:
                t0 = np.random.randint(0, w - t)
                x[:, t0:t0 + t] = 0.0
        return x

    def _mel(self, episode: str) -> np.memmap:
        m = self._mels.get(episode)
        if m is not None:
            self._mels.move_to_end(episode)         # mark most-recently-used
            return m
        m = np.load(self.mel_dir / f"{episode}.npy", mmap_mode="r")
        self._mels[episode] = m
        if len(self._mels) > self._MEL_CACHE_CAP:   # evict LRU + close its fd
            _, evicted = self._mels.popitem(last=False)
            mm = getattr(evicted, "_mmap", None)
            if mm is not None:
                mm.close()  # safe: __getitem__ already copied the slice it needed
        return m

    def __getitem__(self, i):
        w = self.windows[i]
        W = config.WINDOW_FRAMES
        mel = self._mel(w["episode"])               # [n_mels, T_full]
        f0 = w["start_frame"]
        x = np.asarray(mel[:, f0:f0 + W], dtype=np.float32)
        if x.shape[1] < W:                          # right-pad short tail windows
            x = np.pad(x, ((0, 0), (0, W - x.shape[1])))
        if self.augment:
            x = self._spec_augment(x)

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
