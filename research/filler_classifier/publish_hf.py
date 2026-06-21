"""Package, version, and publish Crisp models to Hugging Face — open weights.

Each publish is ONE commit and gets an immutable version tag **v0.0.N** (N = next
sequential, mirroring Crisp's commit-count versioning). So anyone can download an
exact, frozen version:

    https://huggingface.co/<repo>/resolve/v0.0.1/Wren.mlpackage.zip

All artifacts ship (fully open): the Core ML build (`<name>.mlpackage.zip`), the
raw PyTorch weights (`<name>.pt`), a machine-readable `<name>.config.json` (audio
framing + normalization + recommended threshold), and the model card (README).

    # local package + hash only:
    python -m filler_classifier.publish_hf --name Wren

    # publish a new version (after huggingface-cli login):
    python -m filler_classifier.publish_hf --repo you/crisp-models --name Wren \
        --mlpackage checkpoints/Wren.mlpackage --weights checkpoints/filler_cnn.pt \
        --card filler_classifier/MODEL_CARD.md
"""
import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

from . import config


def zip_mlpackage(src: Path, dst: Path) -> None:
    """Zip the .mlpackage dir, keeping its top-level folder so it unzips cleanly."""
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(src.parent))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def next_version(api, repo: str) -> str:
    """Next v0.0.N from existing tags (1 if none) — deterministic, one bump/release."""
    try:
        tags = [t.name.rsplit("/", 1)[-1] for t in api.list_repo_refs(repo, repo_type="model").tags]
    except Exception:
        tags = []
    nums = [int(t[5:]) for t in tags if t.startswith("v0.0.") and t[5:].isdigit()]
    return f"0.0.{(max(nums) + 1) if nums else 1}"


def model_config(name: str, version: str) -> dict:
    """The spec needed to RUN the model — read by the host (incl. the Swift helper)."""
    return {
        "name": name,
        "version": version,
        "task": "filler-word-detection",
        "sample_rate": config.SAMPLE_RATE,
        "n_fft": config.N_FFT,
        "hop_length": config.HOP_LENGTH,
        "n_mels": config.N_MELS,
        "chunk_frames": config.CHUNK_FRAMES,
        "chunk_sec": config.CHUNK_SEC,
        "chunk_hop_sec": config.CHUNK_HOP_SEC,
        "mel_mean": config.MEL_MEAN,
        "mel_std": config.MEL_STD,
        "recommended_threshold": 0.7,
        "input_shape": [1, 1, config.N_MELS, config.CHUNK_FRAMES],
        "output": "filler_prob",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="Wren", help="model name (file prefix)")
    ap.add_argument("--mlpackage", default="checkpoints/FillerClassifier.mlpackage")
    ap.add_argument("--weights", default="checkpoints/filler_cnn.pt", help="raw PyTorch weights")
    ap.add_argument("--card", help="model card .md → uploaded as README.md")
    ap.add_argument("--repo", help="HF repo id, e.g. you/crisp-models (publishes if set)")
    a = ap.parse_args()

    src = Path(a.mlpackage)
    if not src.exists():
        raise SystemExit(f"{src} not found — run export_coreml first.")

    if not a.repo:
        out = Path("checkpoints") / f"{a.name}.mlpackage.zip"
        zip_mlpackage(src, out)
        print(f"packaged {out}  ({out.stat().st_size:,} bytes)\nsha256: {sha256(out)}")
        print("(no --repo; local package only — pass --repo to publish a version)")
        return

    from huggingface_hub import HfApi, create_repo, create_tag
    api = HfApi()
    create_repo(a.repo, repo_type="model", exist_ok=True, private=False)  # public: app downloads w/o auth
    version = next_version(api, a.repo)

    # Stage every artifact, then upload as ONE commit (so 1 release = 1 version bump).
    stage = Path(tempfile.mkdtemp())
    zip_name = f"{a.name}.mlpackage.zip"
    zip_mlpackage(src, stage / zip_name)
    shutil.copy(a.weights, stage / f"{a.name}.pt")                       # open weights
    (stage / f"{a.name}.config.json").write_text(
        json.dumps(model_config(a.name, version), indent=2))
    if a.card:
        shutil.copy(a.card, stage / "README.md")

    api.upload_folder(folder_path=str(stage), repo_id=a.repo, repo_type="model",
                      commit_message=f"{a.name} v{version}")
    create_tag(a.repo, tag=f"v{version}", repo_type="model")

    digest = sha256(stage / zip_name)
    size = (stage / zip_name).stat().st_size
    pinned = f"https://huggingface.co/{a.repo}/resolve/v{version}/{zip_name}"
    print(f"\npublished {a.name} v{version}  →  tag v{version}")
    print(f"  files: {zip_name}, {a.name}.pt, {a.name}.config.json, README.md")
    print(f"  pinned url: {pinned}")
    print(f"  sha256: {digest}   ({size:,} bytes)\n")
    print("--- ModelSpec (pin to this version) for CrispCore/Model/ModelCatalog.swift ---")
    print(f'    url:         URL(string: "{pinned}")!,')
    print(f'    sha256:      "{digest}",')
    print(f'    approxBytes: {size},')


if __name__ == "__main__":
    main()
