"""Loaders for public filler/disfluency corpora → (chunk, label) datasets.

Both corpora are read into the SAME chunk format the model trains on, via the
shared `features.chunk_at` + a binary filler label. We take one representative
chunk per clip so memory stays flat and startup is instant on 60k+ clips —
enough to train a first model and watch it learn.

  PodcastFillers — filler = label_consolidated_vocab in {Uh, Um}. The
    event_start/end_inclip columns place the filler precisely inside each 1 s clip,
    so the positive chunk is sampled right over the "um". Has built-in
    train/validation/test/extra splits (clip_split_subset).
    NOTE: podcast_filename contains commas, so the CSV MUST be parsed with the csv
    module (column-splitting by comma corrupts later fields).

  SEP-28k — filler = the Interjection annotator count >= min_votes. Labels are
    clip-level (no within-clip timing), so it's a coarser signal — we label the
    clip center. Needs its audio downloaded first: run download_audio.py then
    extract_clips.py in the dataset repo (the clone ships only labels + scripts).
"""
from __future__ import annotations

import csv
from pathlib import Path

import torch
from torch.utils.data import Dataset

from .. import config, features


def _pos_weight(labels: torch.Tensor) -> torch.Tensor:
    """BCE pos_weight to offset class imbalance (fillers are the rare class)."""
    pos = float(labels.sum())
    neg = float(len(labels)) - pos
    return torch.tensor(neg / pos) if (pos and neg) else torch.tensor(1.0)  # single-class → no reweighting


class _ChunkDataset(Dataset):
    """Holds (clip_path, center_sec, label) rows; loads one chunk lazily per item."""

    def __init__(self, rows):
        self.rows = rows
        self.labels = torch.tensor([r[2] for r in rows], dtype=torch.float32)

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        path, center, label = self.rows[i]
        waveform = features.load_waveform(str(path))
        patch = features.chunk_at(waveform, center)
        return patch, torch.tensor(float(label), dtype=torch.float32)

    def pos_weight(self):
        return _pos_weight(self.labels)


# ---------------------------------------------------------------- PodcastFillers

PF_FILLERS = {"Uh", "Um"}


def podcastfillers(root, splits=("train",)):
    """root = …/PodcastFillers (the extracted dataset dir)."""
    root = Path(root)
    csv_path = root / "metadata" / "PodcastFillers.csv"
    clip_dir = root / "audio" / "clip_wav"
    if not csv_path.exists():
        raise SystemExit(f"PodcastFillers.csv not found at {csv_path}. "
                         "Point --data at the extracted PodcastFillers/ dir.")

    rows = []
    with open(csv_path, newline="") as f:
        for r in csv.DictReader(f):
            split = r["clip_split_subset"]
            if split not in splits:
                continue
            path = clip_dir / split / r["clip_name"]     # clips are nested by split
            if not path.exists():
                continue
            if r["label_consolidated_vocab"] in PF_FILLERS:
                start = float(r["event_start_inclip"])
                end = float(r["event_end_inclip"])
                rows.append((path, (start + end) / 2.0, 1))     # chunk over the filler
            else:
                mid = (float(r["clip_end_inepisode"]) - float(r["clip_start_inepisode"])) / 2.0
                rows.append((path, mid, 0))                      # clean negative
    if not rows:
        raise SystemExit(f"No PodcastFillers clips found under {root} for splits {splits}.")
    return _ChunkDataset(rows)


# --------------------------------------------------------------------- SEP-28k

def sep28k(root, splits=("train",), label_file="SEP-28k_labels.csv", min_votes=2):
    """root = the ml-stuttering-events-dataset clone (with audio extracted to clips/).

    `splits` is accepted for a uniform interface but SEP-28k ships no split column,
    so it's ignored here — caller (train.py) does the train/val split.
    """
    root = Path(root)
    labels_csv = root / label_file
    clips_root = root / "clips"
    if not labels_csv.exists():
        raise SystemExit(f"{label_file} not found at {labels_csv}.")

    rows = []
    with open(labels_csv, newline="") as f:
        reader = csv.reader(f)
        header = [h.strip() for h in next(reader)]
        col = {name: k for k, name in enumerate(header)}
        for parts in reader:
            parts = [p.strip() for p in parts]
            show, ep, clip = parts[col["Show"]], parts[col["EpId"]], parts[col["ClipId"]]
            path = clips_root / show / ep / f"{show}_{ep}_{clip}.wav"
            if not path.exists():
                continue
            dur = (int(parts[col["Stop"]]) - int(parts[col["Start"]])) / config.SAMPLE_RATE
            label = 1 if int(parts[col["Interjection"]]) >= min_votes else 0
            rows.append((path, dur / 2.0, label))                # clip-level → center chunk
    if not rows:
        raise SystemExit(
            f"No SEP-28k clips found under {clips_root}. Download + extract audio "
            "first: run download_audio.py then extract_clips.py in the dataset repo.")
    return _ChunkDataset(rows)


# ---------------------------------------------------------------------- dispatch

def build(name, root, splits=("train",)):
    if name == "podcastfillers":
        return podcastfillers(root, splits)
    if name == "sep28k":
        return sep28k(root, splits)
    raise SystemExit(f"Unknown corpus {name!r} (expected 'podcastfillers' or 'sep28k').")
