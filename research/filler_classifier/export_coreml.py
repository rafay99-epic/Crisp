"""Export a trained checkpoint to a Core ML .mlpackage.

    python -m filler_classifier.export_coreml --checkpoint checkpoints/filler_cnn.pt

The shipped engine backend feeds one log-mel chunk [1, 1, n_mels, CHUNK_FRAMES]
and reads back P(filler). Feature extraction (mel + chunking) stays in the host,
so the model is a pure tensor→scalar function — easy to verify against infer.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch

from . import config
from .model import FillerCNN


def export(checkpoint, out):
    import coremltools as ct

    # Load weights directly (not via infer.load_model) so the export environment
    # needs only torch + coremltools — no torchaudio/audio stack.
    base = FillerCNN()
    base.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    base.eval()

    class Prob(torch.nn.Module):
        """Fold the sigmoid in so the Core ML output is P(filler) directly."""

        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            return torch.sigmoid(self.m(x))

    wrapped = Prob(base).eval()
    example = torch.zeros(1, 1, config.N_MELS, config.CHUNK_FRAMES)
    traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="chunk", shape=example.shape)],
        outputs=[ct.TensorType(name="filler_prob")],
        minimum_deployment_target=ct.target.macOS13,
    )
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(out)
    print(f"saved {out}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    p.add_argument("--out", default="checkpoints/FillerClassifier.mlpackage")
    a = p.parse_args()
    export(a.checkpoint, a.out)


if __name__ == "__main__":
    main()
