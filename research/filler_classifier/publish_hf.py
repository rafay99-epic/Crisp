"""Package the Core ML model and (optionally) publish it to Hugging Face.

The app downloads a *single file*, but a `.mlpackage` is a directory — so we zip
it. This always zips + computes the SHA-256 and byte size (the two values the
app's ModelSpec needs), and prints a ready-to-paste snippet. With `--repo` and a
HF login, it also uploads.

    # package + hash only (no account needed):
    python -m filler_classifier.publish_hf --name Razor.mlpackage.zip

    # also upload (after: pip install huggingface_hub && huggingface-cli login):
    python -m filler_classifier.publish_hf --repo you/crisp-models --name Razor.mlpackage.zip
"""
import argparse
import hashlib
import zipfile
from pathlib import Path


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mlpackage", default="checkpoints/FillerClassifier.mlpackage")
    ap.add_argument("--name", default="FillerClassifier.mlpackage.zip",
                    help="file name in the HF repo (use the model's cool name)")
    ap.add_argument("--out", default="checkpoints", help="dir to write the zip into")
    ap.add_argument("--repo", help="HF repo id, e.g. you/crisp-models (uploads if set)")
    ap.add_argument("--card", help="model card .md to upload as the repo README.md")
    a = ap.parse_args()

    src = Path(a.mlpackage)
    if not src.exists():
        raise SystemExit(f"{src} not found — run export_coreml first.")

    out = Path(a.out) / a.name
    zip_mlpackage(src, out)
    digest = sha256(out)
    size = out.stat().st_size
    print(f"packaged {out}  ({size:,} bytes)\nsha256: {digest}\n")

    if a.repo:
        from huggingface_hub import HfApi, create_repo
        api = HfApi()
        create_repo(a.repo, repo_type="model", exist_ok=True, private=False)  # public: app downloads w/o auth
        api.upload_file(path_or_fileobj=str(out), path_in_repo=a.name,
                        repo_id=a.repo, repo_type="model")
        if a.card:
            api.upload_file(path_or_fileobj=a.card, path_in_repo="README.md",
                            repo_id=a.repo, repo_type="model")
        url = f"https://huggingface.co/{a.repo}/resolve/main/{a.name}"
        print(f"uploaded → {url}\n")
    else:
        url = f"https://huggingface.co/<your-repo>/resolve/main/{a.name}"
        print("(no --repo given; packaged locally only)\n")

    print("--- paste into CrispCore/Model/ModelCatalog.swift (a ModelSpec) ---")
    print(f'    url:         URL(string: "{url}")!,')
    print(f'    sha256:      "{digest}",')
    print(f'    approxBytes: {size},')


if __name__ == "__main__":
    main()
