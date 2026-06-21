"""Package, version, and publish Crisp models to Hugging Face — open weights.

Uploads the model as a **single raw file** (`<name>.mlmodel`) the app downloads
directly (no zip/unzip). Each publish is **one commit**, and the version is the
repo's **commit count** (`0.0.N`, mirroring Crisp's `0.<commits>` scheme) — so it's
deterministic and never goes backwards. The release is tagged `v0.0.N`:

    https://huggingface.co/<repo>/resolve/v0.0.5/Wren.mlmodel

**Channels mirror the app's release flow** (`--channel`, default `nightly`):
publishing lands on a branch — `nightly` for staging, `main` for stable — so a
new model never reaches Stable users straight from training. Nightly + Dev apps
poll the `nightly` branch's manifest; Stable polls `main`. You promote a tested
model `nightly → main` with `promote_model.py` (the model mirror of
`.github/scripts/promote.sh`). Tags are global refs, so a model published to
`nightly` is already fetchable by its `v0.0.N` pin from anywhere — promotion only
flips which version the stable manifest advertises.

Everything ships open: the Core ML model, the raw PyTorch weights (`<name>.pt`),
a machine-readable `<name>.config.json` (framing + normalization + input/output
names, so the host reads them instead of hardcoding), and the model card.

    # publish a freshly trained model to the nightly (staging) channel:
    python -m filler_classifier.publish_hf --repo you/crisp-models --name Wren \
        --model checkpoints/Wren.mlmodel --weights checkpoints/filler_cnn.pt \
        --card filler_classifier/MODEL_CARD.md
    # then, once it tests well in the Nightly/Dev app, promote it:
    python -m filler_classifier.promote_model --repo you/crisp-models --name Wren
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


# Channel → the HF repo branch its publishes land on. Mirrors the app: `nightly`
# is the staging branch Nightly/Dev poll; `main` is the promoted Stable branch.
BRANCHES = {"nightly": "nightly", "stable": "main"}


def next_version(api, repo: str, branch: str) -> str:
    """Version = (commits so far on the staging branch) + 1 — this publish is one new
    commit. We always count the `nightly` branch, even for a direct stable publish, so
    the counter is a single monotonic line across the model's life (every model goes
    through nightly first). Falls back to `main`, then 0, when nightly doesn't exist yet."""
    from huggingface_hub.utils import RevisionNotFoundError
    for rev in ("nightly", "main"):
        try:
            return f"0.0.{len(api.list_repo_commits(repo, repo_type='model', revision=rev)) + 1}"
        except RevisionNotFoundError:
            # That branch doesn't exist yet — try the next. Real API/auth/network
            # failures aren't swallowed here; they propagate.
            continue
    return "0.0.1"


def model_config(name: str, version: str, channel: str, model_file: str, model_sha256: str) -> dict:
    """Everything the host needs to RUN the model (the helper reads these instead of
    hardcoding) AND to UPDATE it: the config on `main` is the manifest the app polls
    — `version` + `model_sha256` let it detect and verify a newer model."""
    return {
        "name": name,
        "version": version,
        "channel": channel,
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
    ap.add_argument("--channel", choices=list(BRANCHES), default="nightly",
                    help="release channel → HF branch: 'nightly' (staging, default) or "
                         "'stable' (main). Stable is normally reached via promote_model, "
                         "not a direct publish.")
    a = ap.parse_args()

    model = Path(a.model)
    if not model.exists():
        raise SystemExit(f"{model} not found — run export_coreml first.")
    # Validate the other inputs up front, so a wrong path fails with a clear message
    # instead of a shutil traceback mid-publish (after the repo/branch were touched).
    if not Path(a.weights).exists():
        raise SystemExit(f"{a.weights} not found — pass --weights to the .pt file.")
    if a.card and not Path(a.card).exists():
        raise SystemExit(f"{a.card} not found — pass --card to the model card .md.")

    if not a.repo:
        print(f"{model}  ({model.stat().st_size:,} bytes)\nsha256: {sha256(model)}")
        print("(no --repo; pass it to publish a version)")
        return

    branch = BRANCHES[a.channel]
    from huggingface_hub import (HfApi, create_repo, create_branch, create_tag,
                                 CommitOperationAdd, CommitOperationDelete)
    api = HfApi()
    create_repo(a.repo, repo_type="model", exist_ok=True, private=False)  # public: app downloads w/o auth
    # Ensure the channel branch exists (nightly is forked off main the first time).
    create_branch(a.repo, branch=branch, repo_type="model", exist_ok=True)
    version = next_version(api, a.repo, branch)

    model_file = f"{a.name}.mlmodel"
    digest = sha256(model)        # goes into the manifest (config.json) so the app can verify updates
    stage = Path(tempfile.mkdtemp())
    shutil.copy(model, stage / model_file)
    shutil.copy(a.weights, stage / f"{a.name}.pt")                      # open weights
    (stage / f"{a.name}.config.json").write_text(
        json.dumps(model_config(a.name, version, a.channel, model_file, digest), indent=2))
    new_files = [model_file, f"{a.name}.pt", f"{a.name}.config.json"]
    if a.card:
        shutil.copy(a.card, stage / "README.md")
        new_files.append("README.md")

    # One commit on the channel branch: add the new files, and clean up any stale
    # artifacts for this model (e.g. an old <name>.mlpackage.zip) so the repo stays
    # tidy without extra commits.
    existing = set(api.list_repo_files(a.repo, repo_type="model", revision=branch))
    stale = [f for f in existing if f.startswith(f"{a.name}.") and f not in new_files]
    ops = [CommitOperationAdd(path_in_repo=f, path_or_fileobj=str(stage / f)) for f in new_files]
    ops += [CommitOperationDelete(path_in_repo=f) for f in stale]
    api.create_commit(repo_id=a.repo, repo_type="model", operations=ops, revision=branch,
                      commit_message=f"{a.name} v{version} ({a.channel})")
    create_tag(a.repo, tag=f"v{version}", repo_type="model", revision=branch)

    size = model.stat().st_size
    pinned = f"https://huggingface.co/{a.repo}/resolve/v{version}/{model_file}"
    print(f"\npublished {a.name} v{version}  →  {a.channel} branch '{branch}'  (tag v{version})")
    if stale:
        print(f"  removed stale: {stale}")
    print(f"  files: {', '.join(new_files)}")
    print(f"  pinned url: {pinned}")
    print(f"  sha256: {digest}   ({size:,} bytes)\n")
    print("--- ModelSpec (pin to this version) for CrispCore/Model/ModelCatalog.swift ---")
    print(f'    url:         URL(string: "{pinned}")!,')
    print(f'    sha256:      "{digest}",')
    print(f'    approxBytes: {size},')
    if a.channel == "nightly":
        print("\nNightly + Dev apps will offer this update now. Once it tests well, promote it:")
        print(f"  python -m filler_classifier.promote_model --repo {a.repo} --name {a.name}")


if __name__ == "__main__":
    main()
