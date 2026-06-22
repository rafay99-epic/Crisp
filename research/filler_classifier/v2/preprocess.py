"""Wren v2, Phase 1 — turn episodes + derived labels into training windows.

Two outputs, written under <out>/:
  • mels/<episode>.npy — the full-episode log-mel [n_mels, T] (fixed-constant
    normalized, float16), computed once so training never re-decodes audio.
  • windows_<split>.jsonl — one training window per line: which episode, the start
    frame, and the removable-filler spans inside it (in absolute frames).

Window policy (this is where the removable-vs-natural signal is taught):
  • POSITIVE — a WINDOW_SEC window around each *removable* (isolated) filler, jittered
    so the filler isn't always centered. Its label marks only the removable frames;
    any natural filler that happens to share the window stays 0.
  • NEGATIVE — windows with no removable filler. A HARD_NEG_FRAC share are centered on
    a NATURAL/boundary filler (so the model sees "this is a filler sound, but DON'T
    cut it"); the rest are random speech. NEG_PER_POS negatives per positive.

Reuses the engine's ffmpeg to decode mp3 → 16 kHz wav and `features` for the mel, so
the spectrogram matches inference exactly. Run with the torch env (.venv).

    python -m filler_classifier.v2.preprocess --data data/PodcastFillers \
        --labels data/labels_v2/fillers.jsonl --out data/labels_v2 --splits train validation
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch

from .. import config, features

REPO = Path(__file__).resolve().parents[3]
FFMPEG = os.environ.get("CRISP_FFMPEG", "ffmpeg")

REMOVABLE = {"isolated"}                 # the positive class for v1 of the trainer
OTHER_FILLER = {"embedded", "boundary"}  # hard negatives — filler sounds we must keep


def sec_to_frame(t: float) -> int:
    return int(round(t / config.FRAME_SEC))


def episode_mp3(data: Path, split: str, ep: str) -> Path | None:
    p = data / "audio" / "episode_mp3" / split / f"{ep}.mp3"
    return p if p.exists() else None


def compute_mel(mp3: Path) -> np.ndarray:
    """mp3 → [n_mels, T] fixed-normalized log-mel, via ffmpeg + the shared transform."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run([FFMPEG, "-y", "-i", str(mp3), "-vn", "-ac", "1",
                        "-ar", str(config.SAMPLE_RATE), "-c:a", "pcm_s16le", str(wav)],
                       check=True, capture_output=True)
        mel = features.normalize(features.log_mel(features.load_waveform(str(wav))))
    return mel.numpy().astype(np.float16)


def make_windows(fillers, n_frames, rng):
    """Yield (start_frame, [removable spans]) windows for one episode."""
    W = config.WINDOW_FRAMES
    removable, others = [], []
    for f in fillers:
        a, b = sec_to_frame(f["start"]), sec_to_frame(f["end"])
        # Prefer an explicit `removable` label (v3 transcript-grounded labels); fall
        # back to the v2 bucket rule (isolated == removable) when it's absent.
        is_removable = f.get("removable", f["bucket"] in REMOVABLE)
        (removable if is_removable else others).append((a, b))

    def window_around(a, b):
        center = (a + b) // 2
        jitter = int(rng.integers(-W // 3, W // 3 + 1))
        f0 = center - W // 2 + jitter
        return max(0, min(f0, max(0, n_frames - W)))

    def removable_in(f0):
        return [(max(a, f0), min(b, f0 + W)) for a, b in removable if a < f0 + W and b > f0]

    windows = []
    for a, b in removable:                                  # positives
        f0 = window_around(a, b)
        windows.append((f0, removable_in(f0)))

    n_neg = len(removable) * config.NEG_PER_POS
    n_hard = int(n_neg * config.HARD_NEG_FRAC)
    # Hard negatives: centered on a natural/boundary filler, but only if no removable
    # filler falls in the window (else it'd be a positive).
    hard_pool = list(others)
    rng.shuffle(hard_pool)
    for a, b in hard_pool:
        if len([w for w in windows if w[0] == -1]) >= n_hard:
            break
        f0 = window_around(a, b)
        if not removable_in(f0):
            windows.append((f0, []))
    # Random negatives fill the rest.
    tries = 0
    target = len(removable) + n_neg
    while len(windows) < target and tries < target * 20:
        tries += 1
        if n_frames <= W:
            f0 = 0
        else:
            f0 = int(rng.integers(0, n_frames - W))
        if not removable_in(f0):
            windows.append((f0, []))
    return windows


def run(data_dir, labels_path, out_dir, splits, limit=0):
    data_dir, out_dir = Path(data_dir), Path(out_dir)
    mel_dir = out_dir / "mels"
    mel_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(0)

    by_ep = defaultdict(list)
    with open(labels_path) as f:
        for line in f:
            r = json.loads(line)
            by_ep[(r["split"], r["episode"])].append(r)

    for split in splits:
        eps = sorted(k for k in by_ep if k[0] == split
                     and episode_mp3(data_dir, split, k[1]))
        if limit:
            eps = eps[:limit]
        idx_path = out_dir / f"windows_{split}.jsonl"
        n_win = n_pos = n_ep = 0
        with open(idx_path, "w") as out:
            for (sp, ep) in eps:
                mp3 = episode_mp3(data_dir, sp, ep)
                if not mp3:
                    continue
                mel_path = mel_dir / f"{ep}.npy"
                if not mel_path.exists():
                    np.save(mel_path, compute_mel(mp3))
                n_frames = np.load(mel_path, mmap_mode="r").shape[1]
                for f0, spans in make_windows(by_ep[(sp, ep)], n_frames, rng):
                    out.write(json.dumps({"episode": ep, "start_frame": int(f0),
                                          "spans": [[int(a), int(b)] for a, b in spans]}) + "\n")
                    n_win += 1
                    n_pos += 1 if spans else 0
                n_ep += 1
                print(f"  [{split}] {ep[:48]:48} frames={n_frames}")
        print(f"[{split}] {n_ep} episodes → {n_win} windows ({n_pos} positive) → {idx_path}\n")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--labels", default="data/labels_v2/fillers.jsonl")
    p.add_argument("--out", default="data/labels_v2")
    p.add_argument("--splits", nargs="+", default=["train", "validation"])
    p.add_argument("--limit", type=int, default=0, help="cap episodes per split (0 = all; for quick tests)")
    a = p.parse_args()
    run(a.data, a.labels, a.out, a.splits, a.limit)


if __name__ == "__main__":
    main()
