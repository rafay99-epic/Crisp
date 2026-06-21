"""Package, version, and publish Crisp models to Hugging Face — open weights.

Uploads the model as a **single raw file** (`<name>.mlmodel`) the app downloads
directly (no zip/unzip). Each publish is **one commit**, and the version is the
repo's **commit count** (`0.0.N`, mirroring Crisp's `0.<commits>` scheme) — so it's
deterministic and never goes backwards. The release is tagged `v0.0.N`:

    https://huggingface.co/<repo>/resolve/v0.0.5/Wren.mlmodel

Everything ships open: the Core ML model, the raw PyTorch weights (`<name>.pt`),
a machine-readable `<name>.config.json` (framing + normalization + input/output
names, so the host reads them instead of hardcoding), and the model card.

    python -m filler_classifier.publish_hf --repo you/crisp-models --name Wren \
        --model checkpoints/Wren.mlmodel --weights checkpoints/filler_cnn.pt \
        --card filler_classifier/MODEL_CARD.md
"""
import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

from . import config


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def next_version(api, repo: str) -> str:
    """Version = (commits so far) + 1 — this publish is exactly one new commit."""
    try:
        n = len(api.list_repo_commits(repo, repo_type="model"))
    except Exception:
        n = 0
    return f"0.0.{n + 1}"


def model_config(name: str, version: str, model_file: str, model_sha256: str) -> dict:
    """Everything the host needs to RUN the model (the helper reads these instead of
    hardcoding) AND to UPDATE it: the config on `main` is the manifest the app polls
    — `version` + `model_sha256` let it detect and verify a newer model."""
    return {
        "name": name,
        "version": version,
        "task": "filler-word-detection",
        "model_sha256": model_sha256,
        "model_file": model_file,
        "input": "chunk",
        "output": "filler_prob",
        "input_shape": [1, 1, config.N_MELS, config.CHUNK_FRAMES],
        "sample_rate": config.SAMPLE_RATE,
        "n_fft": config.N_FFT,
        "hop_length": config.HOP_LENGTH,
        "n_mels": config.N_MELS,
        "chunk_frames": config.CHUNK_FRAMES,
        "chunk_sec": config.CHUNK_SEC,
        "chunk_hop_sec": config.CHUNK_HOP_SEC,
        "mel_mean": config.MEL_MEAN,
        "mel_std": config.MEL_STD,
        # Per-model tuning, read by the crisp-filler helper (so values aren't hardcoded).
        "recommended_threshold": 0.85,   # conservative for real, word-dominated footage
        "min_filler": 0.30,              # drop fleeting fillers (a real "uhh" is longer)
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="Wren", help="model name (file prefix)")
    ap.add_argument("--model", default="checkpoints/Wren.mlmodel", help="the .mlmodel to publish")
    ap.add_argument("--weights", default="checkpoints/filler_cnn.pt", help="raw PyTorch weights")
    ap.add_argument("--card", help="model card .md → uploaded as README.md")
    ap.add_argument("--repo", help="HF repo id, e.g. you/crisp-models (publishes if set)")
    a = ap.parse_args()

    model = Path(a.model)
    if not model.exists():
        raise SystemExit(f"{model} not found — run export_coreml first.")

    if not a.repo:
        print(f"{model}  ({model.stat().st_size:,} bytes)\nsha256: {sha256(model)}")
        print("(no --repo; pass it to publish a version)")
        return

    from huggingface_hub import (HfApi, create_repo, create_tag,
                                 CommitOperationAdd, CommitOperationDelete)
    api = HfApi()
    create_repo(a.repo, repo_type="model", exist_ok=True, private=False)  # public: app downloads w/o auth
    version = next_version(api, a.repo)

    model_file = f"{a.name}.mlmodel"
    digest = sha256(model)        # goes into the manifest (config.json) so the app can verify updates
    stage = Path(tempfile.mkdtemp())
    shutil.copy(model, stage / model_file)
    shutil.copy(a.weights, stage / f"{a.name}.pt")                      # open weights
    (stage / f"{a.name}.config.json").write_text(
        json.dumps(model_config(a.name, version, model_file, digest), indent=2))
    new_files = [model_file, f"{a.name}.pt", f"{a.name}.config.json"]
    if a.card:
        shutil.copy(a.card, stage / "README.md")
        new_files.append("README.md")

    # One commit: add the new files, and clean up any stale artifacts for this model
    # (e.g. an old <name>.mlpackage.zip) so the repo stays tidy without extra commits.
    existing = set(api.list_repo_files(a.repo, repo_type="model"))
    stale = [f for f in existing if f.startswith(f"{a.name}.") and f not in new_files]
    ops = [CommitOperationAdd(path_in_repo=f, path_or_fileobj=str(stage / f)) for f in new_files]
    ops += [CommitOperationDelete(path_in_repo=f) for f in stale]
    api.create_commit(repo_id=a.repo, repo_type="model", operations=ops,
                      commit_message=f"{a.name} v{version}")
    create_tag(a.repo, tag=f"v{version}", repo_type="model")

    size = model.stat().st_size
    pinned = f"https://huggingface.co/{a.repo}/resolve/v{version}/{model_file}"
    print(f"\npublished {a.name} v{version}  (tag v{version})")
    if stale:
        print(f"  removed stale: {stale}")
    print(f"  files: {', '.join(new_files)}")
    print(f"  pinned url: {pinned}")
    print(f"  sha256: {digest}   ({size:,} bytes)\n")
    print("--- ModelSpec (pin to this version) for CrispCore/Model/ModelCatalog.swift ---")
    print(f'    url:         URL(string: "{pinned}")!,')
    print(f'    sha256:      "{digest}",')
    print(f'    approxBytes: {size},')


if __name__ == "__main__":
    main()
