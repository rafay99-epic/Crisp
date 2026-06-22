"""Phase 0 — derive *removable vs natural* filler labels from PodcastFillers.

Wren v0.0.8 learned "is there an um/uh sound here?" (acoustic). It over-cuts because
it can't tell a removable disfluency (a standalone "um" with a pause around it) from a
natural mid-sentence "hmm". v2 needs labels for *removability*, which requires context.

PodcastFillers gives us exactly that, at episode scale:
  • episode_annotations/<split>/<ep>.csv — each Uh/Um with its precise time in the
    full episode (event_start/end_inepisode) + label + n_annotators.
  • episode_vad/<split>/<ep>.csv — a per-10ms voice-activity probability (0..1) over
    the whole episode (silence ≈ 0, speech ≈ 1).

For each filler we look at the VAD just before and just after it and bucket it:
  • isolated  — real silence on BOTH sides       → REMOVABLE (the clean cut case)
  • boundary  — silence on ONE side only          → softer; the gray zone whisper
                                                     validation (validate_labels.py) resolves
  • embedded  — speech on both sides, no pause     → NATURAL (leave it)

Output is a JSONL of every filler with its raw signals + bucket, consumed by the
whisper validator and (later) the sequence-model trainer. This file is pure stdlib
(csv only) — fast, no torch needed.

    python -m filler_classifier.v2.derive_labels --data data/PodcastFillers \
        --out data/labels_v2
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
from collections import Counter, defaultdict
from pathlib import Path

FILLERS = ("Uh", "Um")

# VAD thresholds (tunable). A "pause" is >=MIN_SIL_SEC of VAD below SIL_THRESH within
# GAP_SEC of the filler edge. Defaults chosen against the VAD distribution (median
# ~0.72, strongly bimodal, so 0.15 sits well inside the silence mode).
SIL_THRESH = 0.15
MIN_SIL_SEC = 0.12
GAP_SEC = 0.35
VAD_STEP = 0.01      # the VAD grid is one sample per 10 ms


def load_vad(path: str) -> list[float]:
    with open(path) as f:
        return [float(v) for _t, v in csv.reader(f)]


def has_pause(vad: list[float], t0: float, t1: float) -> bool:
    """True if a contiguous run of >=MIN_SIL_SEC silence sits within [t0, t1]."""
    i0, i1 = max(0, int(t0 / VAD_STEP)), min(len(vad), int(t1 / VAD_STEP) + 1)
    need, run = int(MIN_SIL_SEC / VAD_STEP), 0
    for v in vad[i0:i1]:
        run = run + 1 if v < SIL_THRESH else 0
        if run >= need:
            return True
    return False


def bucket(sil_before: bool, sil_after: bool) -> str:
    if sil_before and sil_after:
        return "isolated"      # REMOVABLE
    if sil_before or sil_after:
        return "boundary"      # gray zone
    return "embedded"          # NATURAL


def fillers_for_episode(ann_path: str, vad: list[float]):
    """Yield one record per Uh/Um filler in an episode."""
    with open(ann_path) as f:
        for r in csv.DictReader(f):
            if r["label_consolidated_vocab"] not in FILLERS:
                continue
            start = float(r["event_start_inepisode"])
            end = float(r["event_end_inepisode"])
            before = has_pause(vad, start - GAP_SEC, start)
            after = has_pause(vad, end, end + GAP_SEC)
            yield {
                "episode": Path(ann_path).stem,
                "split": ann_path.split(os.sep)[-2],
                "label": r["label_consolidated_vocab"],
                "start": start,
                "end": end,
                "duration": round(end - start, 3),
                "sil_before": before,
                "sil_after": after,
                "bucket": bucket(before, after),
                "n_annotators": int(r.get("n_annotators", 0) or 0),
            }


def run(data_dir: str, out_dir: str):
    meta = Path(data_dir) / "metadata"
    ann_glob = str(meta / "episode_annotations" / "*" / "*.csv")
    episodes = sorted(glob.glob(ann_glob))
    if not episodes:
        raise SystemExit(f"No episode annotations under {ann_glob}. Point --data at PodcastFillers/.")

    Path(out_dir).mkdir(parents=True, exist_ok=True)
    out_path = Path(out_dir) / "fillers.jsonl"
    counts = defaultdict(Counter)
    durs = defaultdict(list)
    n = 0
    with open(out_path, "w") as out:
        for ann in episodes:
            vad_path = ann.replace("episode_annotations", "episode_vad")
            if not os.path.exists(vad_path):
                continue
            vad = load_vad(vad_path)
            for rec in fillers_for_episode(ann, vad):
                out.write(json.dumps(rec) + "\n")
                counts[rec["split"]][rec["bucket"]] += 1
                durs[rec["bucket"]].append(rec["duration"])
                n += 1

    print(f"wrote {n} filler records → {out_path}\n")
    labels = {"isolated": "REMOVABLE", "boundary": "gray", "embedded": "NATURAL"}
    for split in ("train", "validation", "test", "extra"):
        c = counts.get(split)
        if not c:
            continue
        tot = sum(c.values())
        print(f"[{split}]  {tot} Uh/Um fillers")
        for b in ("isolated", "boundary", "embedded"):
            print(f"  {b:9} {labels[b]:10} {c.get(b,0):6}  ({100*c.get(b,0)/tot:4.1f}%)")
    print("\nmean duration by bucket (acoustic separability check):")
    for b in ("embedded", "boundary", "isolated"):
        d = durs.get(b, [])
        if d:
            print(f"  {b:9} {sum(d)/len(d):.3f}s  (n={len(d)})")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/PodcastFillers", help="extracted PodcastFillers/ dir")
    p.add_argument("--out", default="data/labels_v2", help="output dir for fillers.jsonl")
    a = p.parse_args()
    run(a.data, a.out)


if __name__ == "__main__":
    main()
