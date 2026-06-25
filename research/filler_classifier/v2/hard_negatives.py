"""v3 experiment — SEP-28k hard negatives, to stop the model firing on non-speech.

The behavioral test exposed the real error: on a music/comedy episode the model cut
~30 spans and only ~1 was a real filler (3% on-filler). It only ever trained on
PodcastFillers (clean speech + fillers), so it never learned "this is music / noise /
a non-filler disfluency — don't cut."

SEP-28k labels exactly those. We pull clips that are NOT interjections — Music,
NoSpeech, other disfluencies (Prolongation/Block/SoundRep/WordRep), and some clean
speech — and emit them as **all-negative** windows the trainer mixes in. The clip
audio is a [Start:Stop] slice of the episode wav (read once per episode), turned into
the same log-mel windows the model trains on.

    python -m filler_classifier.v2.hard_negatives --data data/ml-stuttering-events-dataset \
        --out data/hardneg --limit 5000
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import wave
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import torch

from .. import config, features

# How many of each non-filler type to pull (weighted toward the error source: the
# model over-fires on music/noise/odd-sounds, so load up on those, less on clean speech).
QUOTA = {"Music": 1.0, "NoSpeech": 1.0, "other-disfluency": 1.0, "clean-speech": 0.35}


def category(r) -> str | None:
    def has(k): return int(r[k]) > 0
    if has("Interjection"):
        return None                       # it's a filler — not a negative
    if has("Music"):
        return "Music"
    if has("NoSpeech"):
        return "NoSpeech"
    if has("Prolongation") or has("Block") or has("SoundRep") or has("WordRep"):
        return "other-disfluency"
    if has("NoStutteredWords"):
        return "clean-speech"
    return None


def clip_mel(wav_path: Path, start: int, stop: int) -> np.ndarray | None:
    """Read the [start:stop] sample slice of an episode wav → padded log-mel [n_mels, W]."""
    try:
        with wave.open(str(wav_path), "rb") as w:
            sr, width, n = w.getframerate(), w.getsampwidth(), w.getnframes()
            if width != 2 or start >= n:
                return None
            w.setpos(start)
            raw = w.readframes(min(stop, n) - start)
    except (OSError, wave.Error):
        return None
    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if sr != config.SAMPLE_RATE or len(data) < config.N_FFT:
        return None
    mel = features.normalize(features.log_mel(torch.from_numpy(data.copy())))   # [n_mels, T]
    W = config.WINDOW_FRAMES
    mel = mel[:, :W]
    if mel.shape[1] < W:                                          # right-pad short clips
        mel = torch.nn.functional.pad(mel, (0, W - mel.shape[1]))
    return mel.numpy().astype(np.float16)


def run(data_dir, out_dir, limit, seed=0):
    data_dir, out_dir = Path(data_dir), Path(out_dir)
    if limit <= 0:
        raise SystemExit("--limit must be > 0")
    rng = random.Random(seed)
    rows = list(csv.DictReader(open(data_dir / "SEP-28k_labels.csv")))

    # Keep only non-filler clips whose episode wav is actually on disk (partial download).
    pool = defaultdict(list)
    for r in rows:
        cat = category(r)                       # int() tolerates the CSV's leading spaces
        if not cat:
            continue
        show, ep = r["Show"].strip(), r["EpId"].strip()    # SEP-28k CSV pads fields with spaces
        wav = data_dir / "wavs" / show / f"{ep}.wav"
        if wav.exists():
            pool[cat].append((show, ep, int(r["Start"]), int(r["Stop"]), cat, wav))
    if not pool:
        raise SystemExit("No SEP-28k clips with audio found — check wavs/ is populated.")

    # Sample to `limit`, weighted by QUOTA.
    wsum = sum(QUOTA[c] * min(len(pool[c]), limit) for c in pool)
    if wsum == 0:
        raise SystemExit("No quota-eligible clips for the requested --limit.")
    picks = []
    for cat, items in pool.items():
        k = min(len(items), int(limit * QUOTA[cat] * min(len(items), limit) / wsum))
        picks += rng.sample(items, k)
    rng.shuffle(picks)

    mel_dir = out_dir / "mels"
    mel_dir.mkdir(parents=True, exist_ok=True)
    idx_path = out_dir / "windows.jsonl"
    by_ep = defaultdict(list)               # group by episode → load each wav once
    for show, ep, s, e, cat, wav in picks:
        by_ep[wav].append((show, ep, s, e, cat))

    counts = Counter()
    n = 0
    with open(idx_path, "w") as out:
        for wav, clips in by_ep.items():
            for show, ep, s, e, cat in clips:
                mel = clip_mel(wav, s, e)
                if mel is None:
                    continue
                cid = f"sep_{show}_{ep}_{s}"
                np.save(mel_dir / f"{cid}.npy", mel)
                out.write(json.dumps({"episode": cid, "start_frame": 0, "spans": []}) + "\n")
                counts[cat] += 1
                n += 1
    print(f"wrote {n} hard-negative windows → {idx_path}")
    for c, k in counts.most_common():
        print(f"  {c:18} {k}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/ml-stuttering-events-dataset")
    p.add_argument("--out", default="data/hardneg")
    p.add_argument("--limit", type=int, default=5000)
    a = p.parse_args()
    run(a.data, a.out, a.limit)


if __name__ == "__main__":
    main()
