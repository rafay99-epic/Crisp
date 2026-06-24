"""v3 — synthetic non-speech hard negatives (no downloads).

The v3 A/B (NOTES §6d) confirmed the lever is negative-class COVERAGE, not the
training recipe: both runs shared the same thin ~400 SEP-28k music/noise clips, so
the model still over-fired on music/noise. This SYNTHESIZES a wide variety of
non-speech audio — white/pink/brown noise, tonal beds & chords with vibrato +
tremolo, AM/FM tones, mains hum, click trains, and mixes of these — and turns each
into the same all-negative log-mel windows the trainer mixes in via `--hard-neg`.

It's the download-free half of the data lever: synthesis covers noise + tonal
over-firing well; real music corpora (FMA/MUSDB18) would add the timbral realism
synthesis can't, and the teacher-distillation path (v3/teacher_labels.py, planned)
scales real negatives further. Output matches `v2/hard_negatives.py` exactly, so
`v2.train --hard-neg data/hardneg data/synthneg …` consumes both.

    python -m filler_classifier.v3.synth_negatives --out data/synthneg --count 5000
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch

from .. import config, features

SR = config.SAMPLE_RATE
N = config.WINDOW_FRAMES * config.HOP_LENGTH      # samples per 4 s window (64000)

# How the synthetic windows are split across categories (weighted toward the error
# sources — tonal "music" and noise are what the model over-fires on).
CATEGORIES = ["noise", "tonal", "music", "ammod", "hum", "clicks", "mix"]
WEIGHTS = np.array([0.20, 0.20, 0.25, 0.10, 0.08, 0.07, 0.10])


def _norm(x: np.ndarray, rng) -> np.ndarray:
    """Scale to a random, realistic peak so the model sees varied loudness."""
    peak = np.max(np.abs(x)) or 1.0
    return (x / peak) * rng.uniform(0.15, 0.9)


def _noise(rng) -> np.ndarray:
    kind = rng.choice(["white", "pink", "brown"])
    w = rng.standard_normal(N)
    if kind == "white":
        return w
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(N, 1 / SR)
    f[0] = f[1]
    spec /= np.sqrt(f) if kind == "pink" else f       # 1/√f (pink) or 1/f (brown)
    return np.fft.irfft(spec, n=N)


def _partials(rng, t, root, n_partials, decay=0.6) -> np.ndarray:
    """Sum of harmonic partials (a crude timbre) with light random vibrato."""
    vib = 1 + 0.005 * np.sin(2 * np.pi * rng.uniform(3, 7) * t)
    out = np.zeros_like(t)
    for k in range(1, n_partials + 1):
        out += (decay ** (k - 1)) * np.sin(2 * np.pi * root * k * t * vib)
    return out


def _tonal(rng) -> np.ndarray:
    t = np.arange(N) / SR
    root = rng.uniform(110, 880)
    sig = _partials(rng, t, root, rng.integers(1, 5))
    trem = 1 + rng.uniform(0, 0.5) * np.sin(2 * np.pi * rng.uniform(2, 8) * t)   # tremolo
    return sig * trem


def _music(rng) -> np.ndarray:
    """A short chord progression (stacked partials) over the window."""
    t = np.arange(N) / SR
    root = rng.uniform(130, 330)
    semis = [[0, 4, 7], [0, 3, 7], [0, 5, 9], [0, 4, 9]][rng.integers(0, 4)]
    n_chords = rng.integers(2, 5)
    out = np.zeros_like(t)
    seg = N // n_chords
    for c in range(n_chords):
        sl = slice(c * seg, (c + 1) * seg if c < n_chords - 1 else N)
        ts = t[sl]
        shift = 2 ** (rng.integers(-2, 3) / 12)
        chord = sum(_partials(rng, ts, root * shift * 2 ** (s / 12), 3) for s in semis)
        out[sl] = chord
    return out


def _ammod(rng) -> np.ndarray:
    t = np.arange(N) / SR
    carrier = np.sin(2 * np.pi * rng.uniform(200, 1200) * t)
    if rng.random() < 0.5:                                   # amplitude modulation
        return carrier * (1 + np.sin(2 * np.pi * rng.uniform(2, 12) * t))
    fm = rng.uniform(40, 200) * np.cumsum(np.sin(2 * np.pi * rng.uniform(1, 6) * t)) / SR
    return np.sin(2 * np.pi * rng.uniform(200, 1200) * t + fm)   # frequency modulation


def _hum(rng) -> np.ndarray:
    t = np.arange(N) / SR
    base = rng.choice([50.0, 60.0, 100.0, 120.0])
    return sum((0.6 ** k) * np.sin(2 * np.pi * base * (k + 1) * t) for k in range(4))


def _clicks(rng) -> np.ndarray:
    out = np.zeros(N)
    for pos in rng.integers(0, N, size=rng.integers(3, 40)):
        ln = rng.integers(20, 400)
        env = np.exp(-np.linspace(0, 6, min(ln, N - pos)))
        out[pos:pos + len(env)] += env * rng.uniform(0.5, 1.0)
    return out + 0.02 * rng.standard_normal(N)


def _build_one(rng, cat) -> np.ndarray:
    return {"noise": _noise, "tonal": _tonal, "music": _music,
            "ammod": _ammod, "hum": _hum, "clicks": _clicks}[cat](rng)


def _build(rng) -> tuple[str, np.ndarray]:
    """Pick a category and synthesize one 4 s non-speech waveform → (category, wav)."""
    cat = rng.choice(CATEGORIES, p=WEIGHTS)
    if cat == "mix":                                        # e.g. a tone/chord over noise
        a = _build_one(rng, rng.choice(["tonal", "music", "hum", "ammod"]))
        x = _norm(a, rng) + rng.uniform(0.1, 0.6) * _norm(_noise(rng), rng)
    else:
        x = _build_one(rng, cat)
    return cat, _norm(x, rng).astype(np.float32)


def window_mel(wav: np.ndarray) -> np.ndarray:
    """Synthetic waveform → padded, normalized log-mel [n_mels, WINDOW_FRAMES] float16
    — identical to what hard_negatives/preprocess cache, so training treats it the same."""
    mel = features.normalize(features.log_mel(torch.from_numpy(wav)))   # [n_mels, T]
    W = config.WINDOW_FRAMES
    mel = mel[:, :W]
    if mel.shape[1] < W:
        mel = torch.nn.functional.pad(mel, (0, W - mel.shape[1]))
    return mel.numpy().astype(np.float16)


def run(out_dir, count, seed=0):
    out_dir = Path(out_dir)
    mel_dir = out_dir / "mels"
    mel_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    idx_path = out_dir / "windows.jsonl"
    from collections import Counter
    cats = Counter()
    with open(idx_path, "w") as out:
        for i in range(count):
            cat, wav = _build(rng)
            cid = f"synth_{cat}_{i:06d}"
            np.save(mel_dir / f"{cid}.npy", window_mel(wav))
            out.write(json.dumps({"episode": cid, "start_frame": 0, "spans": []}) + "\n")
            cats[cat] += 1
    print(f"wrote {count} synthetic negative windows → {idx_path}")
    for c, k in cats.most_common():
        print(f"  {c:8} {k}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", default="data/synthneg")
    p.add_argument("--count", type=int, default=5000)
    p.add_argument("--seed", type=int, default=0)
    a = p.parse_args()
    run(a.out, a.count, a.seed)


if __name__ == "__main__":
    main()
