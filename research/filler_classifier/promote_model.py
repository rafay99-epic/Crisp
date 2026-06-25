"""Promote a model from the `nightly` staging branch to `main` (Stable) on Hugging
Face — the model mirror of `.github/scripts/promote.sh`.

A tested Nightly model becomes the Stable one in **a single commit** that copies
the current `nightly` tip onto `main` (model file, weights, manifest, card). No
branch merge — exactly like the app's promote script, which sets `main`'s tree to
`origin/nightly` in one commit so there's no 3-way merge to conflict on. The model
bytes already exist under their global `v0.0.N` tag, so promotion only changes
which version `main`'s manifest advertises — the file Stable apps poll.

    python -m filler_classifier.promote_model --repo you/crisp-models --name Wren

Pass `--version vX.Y.Z` to promote a specific tag instead of the nightly tip
(e.g. to roll Stable back to a known-good earlier model).
"""
import argparse
import json
import tempfile
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="HF repo id, e.g. you/crisp-models")
    ap.add_argument("--name", default="Wren", help="model name (file prefix)")
    ap.add_argument("--version", default=None,
                    help="promote this exact tag (e.g. v0.0.7) instead of the nightly tip")
    a = ap.parse_args()

    from huggingface_hub import HfApi, hf_hub_download, CommitOperationAdd, CommitOperationDelete
    api = HfApi()

    # The source revision: a pinned tag if given, else the live nightly tip.
    source = a.version if a.version else "nightly"
    files = [f for f in api.list_repo_files(a.repo, repo_type="model", revision=source)
             if f == "README.md" or f.startswith(f"{a.name}.")]
    if not files:
        raise SystemExit(f"no '{a.name}.*' files on '{source}' — publish to nightly first.")

    # Read the manifest so we can report (and verify) exactly what's being promoted.
    cfg_path = hf_hub_download(a.repo, f"{a.name}.config.json", repo_type="model", revision=source)
    manifest = json.loads(Path(cfg_path).read_text())
    version = manifest.get("version", "?")

    # Flip the manifest's channel marker to stable as it lands on main (cosmetic — the
    # app keys off the branch it polls, not this field, but it keeps the file honest).
    stage = Path(tempfile.mkdtemp())
    ops = []
    for f in files:
        local = hf_hub_download(a.repo, f, repo_type="model", revision=source)
        if f == f"{a.name}.config.json":
            m = json.loads(Path(local).read_text())
            m["channel"] = "stable"
            dest = stage / f
            dest.write_text(json.dumps(m, indent=2))
            ops.append(CommitOperationAdd(path_in_repo=f, path_or_fileobj=str(dest)))
        else:
            ops.append(CommitOperationAdd(path_in_repo=f, path_or_fileobj=local))

    # Remove anything for this model on main that the promoted set no longer includes,
    # so main is exactly the nightly tip's file set — one commit, no merge.
    on_main = set(api.list_repo_files(a.repo, repo_type="model", revision="main"))
    stale = [f for f in on_main if (f == "README.md" or f.startswith(f"{a.name}.")) and f not in files]
    ops += [CommitOperationDelete(path_in_repo=f) for f in stale]

    api.create_commit(repo_id=a.repo, repo_type="model", operations=ops, revision="main",
                      commit_message=f"Promote {a.name} v{version} to stable")

    print(f"\npromoted {a.name} v{version}  ({source} → main / stable)")
    if stale:
        print(f"  removed stale on main: {stale}")
    print("  Stable apps will now offer this model on their next update check.\n")
    print("Remember to pin the floor in FillerModelCatalog.swift to this version:")
    print(f"  https://huggingface.co/{a.repo}/resolve/v{version}/{a.name}.mlmodel")


if __name__ == "__main__":
    main()
