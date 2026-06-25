"""Export Wren v2 (WrenSeq) to a single-file Core ML .mlmodel with a flexible length.

    ./.venv-export/bin/python -m filler_classifier.v2.export_coreml \
        --checkpoint checkpoints/wren_seq.pt

Unlike the chunk model (fixed [1,1,n_mels,25] input), v2 is fully convolutional, so
the Core ML model takes a **variable-length** log-mel sequence [1, n_mels, T] and
returns per-frame P(removable) [1, T]. The host computes the mel (same fixed-constant
normalization) and feeds the whole recording in one call. The sigmoid is folded in so
the output is already a probability.

Run in the Python 3.10 export env (.venv-export) — coremltools' BlobWriter has no
bleeding-edge-Python build. Prints a PyTorch-vs-CoreML parity check.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch import nn

from .. import config
from .model import WrenSeq

IN_NAME = "mel"
OUT_NAME = "removable_prob"


class Prob(nn.Module):
    """Fold sigmoid in → Core ML output is P(removable) per frame directly."""

    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):                       # x: [1, n_mels, T]
        return torch.sigmoid(self.m(x))         # [1, T]


def export(checkpoint, out):
    import coremltools as ct

    base = WrenSeq()
    base.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    base.eval()
    wrapped = Prob(base).eval()

    example = torch.zeros(1, config.N_MELS, config.WINDOW_FRAMES)
    traced = torch.jit.trace(wrapped, example)

    # Flexible time axis: from one chunk's worth of frames up to an unbounded length,
    # so a whole recording can be fed in one call.
    time_dim = ct.RangeDim(lower_bound=config.CHUNK_FRAMES, upper_bound=-1,
                           default=config.WINDOW_FRAMES)
    shape = ct.Shape(shape=(1, config.N_MELS, time_dim))
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name=IN_NAME, shape=shape)],
        convert_to="neuralnetwork",
    )
    spec = mlmodel.get_spec()
    on = spec.description.output[0].name
    if on != OUT_NAME:
        ct.utils.rename_feature(spec, on, OUT_NAME)
        mlmodel = ct.models.MLModel(spec)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(out)
    print(f"saved {out}  (input='{IN_NAME}' [1,{config.N_MELS},T], output='{OUT_NAME}' [1,T])")

    # Write the self-describing config.json sidecar (the helper reads model_type +
    # framing from it; publish_hf later adds version + model_sha256 for the manifest).
    cfg = {
        "name": Path(out).stem,
        "generation": 2,
        "model_type": "sequence",
        "input": IN_NAME,
        "output": OUT_NAME,
        "sample_rate": config.SAMPLE_RATE,
        "n_fft": config.N_FFT,
        "hop_length": config.HOP_LENGTH,
        "n_mels": config.N_MELS,
        "mel_mean": config.MEL_MEAN,
        "mel_std": config.MEL_STD,
        "recommended_threshold": 0.9,   # the sweep's F1 peak; favors precision (less over-cutting)
        "min_filler": 0.08,
    }
    cfg_path = Path(out).with_suffix(".config.json")
    cfg_path.write_text(json.dumps(cfg, indent=2))
    print(f"saved {cfg_path}")

    # Parity: the helper relies on Core ML matching PyTorch. Check a few lengths.
    # Tolerance 2e-3: per-frame probabilities only ever feed a threshold + span merge,
    # so a sub-thousandth difference can't change a cut. A real export bug shows 0.1+.
    import numpy as np
    torch.manual_seed(0)
    for T in (config.WINDOW_FRAMES, 1000, 3000):
        x = torch.randn(1, config.N_MELS, T)
        with torch.no_grad():
            ref = wrapped(x).numpy()
        got = mlmodel.predict({IN_NAME: x.numpy()})[OUT_NAME]
        diff = float(np.abs(ref - got).max())
        print(f"  parity T={T:5}: max|Δ| = {diff:.2e}  {'OK' if diff < 2e-3 else 'FAIL'}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--checkpoint", default="checkpoints/wren_seq.pt")
    # Built models live under research/models/<name>/ — in the repo, gitignored,
    # never pushed (published to Hugging Face via the dev flow instead).
    p.add_argument("--out", default="models/wren-v2/Wren.mlmodel")
    a = p.parse_args()
    export(a.checkpoint, a.out)


if __name__ == "__main__":
    main()
