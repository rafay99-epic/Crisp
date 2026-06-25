"""v3 experiment — language-grounded *removability* labels (transcript + VAD).

The v2 labels called a filler removable only if VAD found silence on BOTH sides
(`bucket == isolated`, ~17%). That's a crude proxy and it throws away the ~50%
"boundary" gray zone. PodcastFillers ships **episode transcripts** (Azure ASR, word
-level timing), so we can do far better with no whisper run:

  A filler that is **tightly bracketed by spoken words on both sides** can't be cleanly
  cut — you'd clip the neighbouring words → it's a woven-in hesitation → NATURAL.
  A filler with a real gap to the nearest spoken word on **at least one side** is
  detachable (a leading/trailing/standalone hesitation) → REMOVABLE.

We fuse two signals per side: a transcript word-gap (>= WORD_GAP) OR a VAD pause. A
filler is removable if it's detached on both sides. This is the language context the
v2 VAD-only rule lacked — and it's free (transcripts + VAD already on disk, stdlib).

    python -m filler_classifier.v2.relabel --data data/PodcastFillers --out data/labels_v3
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
from bisect import bisect_left, bisect_right
from collections import Counter, defaultdict
from pathlib import Path

from .derive_labels import FILLERS, GAP_SEC, bucket, has_pause, load_vad

WORD_GAP = 0.20      # gap (s) to the nearest spoken word that counts as "detached"
OFFSET_UNIT = 1e7    # transcript offsets are in 100-ns ticks → seconds


def load_word_bounds(path: str):
    """Transcript JSON → (sorted word-end times, sorted word-start times)."""
    try:
        d = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    starts, ends = [], []
    for seg in d.get("segments", []):
        for nb in (seg.get("nbest") or [])[:1]:            # top hypothesis only
            for w in nb.get("words", []):
                s = w["offset"] / OFFSET_UNIT
                starts.append(s)
                ends.append(s + w.get("duration", 0) / OFFSET_UNIT)
    starts.sort()
    ends.sort()
    return (ends, starts) if starts else None


def word_gaps(bounds, fs: float, fe: float):
    """Gap to the nearest spoken word before the filler start and after its end."""
    ends, starts = bounds
    # nearest word END at/just before the filler start
    i = bisect_right(ends, fs + 0.05)
    gap_before = (fs - ends[i - 1]) if i > 0 else 99.0
    # nearest word START at/just after the filler end
    j = bisect_left(starts, fe - 0.05)
    gap_after = (starts[j] - fe) if j < len(starts) else 99.0
    return max(0.0, gap_before), max(0.0, gap_after)


def run(data_dir, out_dir):
    meta = Path(data_dir) / "metadata"
    episodes = sorted(glob.glob(str(meta / "episode_annotations" / "*" / "*.csv")))
    if not episodes:
        raise SystemExit(f"No annotations under {meta}/episode_annotations. Point --data at PodcastFillers/.")
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    out_path = Path(out_dir) / "fillers.jsonl"

    counts = defaultdict(Counter)
    flip = Counter()                 # how v3 differs from the v2 (isolated-only) label
    n = n_tr = 0
    with open(out_path, "w") as out:
        for ann in episodes:
            vad_path = ann.replace("episode_annotations", "episode_vad")
            tr_path = ann.replace("episode_annotations", "episode_transcripts")[:-4] + ".json"
            if not os.path.exists(vad_path):
                continue
            vad = load_vad(vad_path)
            bounds = load_word_bounds(tr_path)              # may be None (no transcript)
            n_tr += bounds is not None
            split = ann.split(os.sep)[-2]
            with open(ann) as f:
                for r in csv.DictReader(f):
                    if r["label_consolidated_vocab"] not in FILLERS:
                        continue
                    fs = float(r["event_start_inepisode"])
                    fe = float(r["event_end_inepisode"])
                    sil_b = has_pause(vad, fs - GAP_SEC, fs)
                    sil_a = has_pause(vad, fe, fe + GAP_SEC)
                    if bounds:
                        gb, ga = word_gaps(bounds, fs, fe)
                    else:                                   # no transcript → fall back to VAD only
                        gb = 99.0 if sil_b else 0.0
                        ga = 99.0 if sil_a else 0.0
                    detached_before = gb >= WORD_GAP or sil_b
                    detached_after = ga >= WORD_GAP or sil_a
                    # Conservative "should cut" rule: removable only if genuinely
                    # standalone — a gap/pause on BOTH sides. (Detached on just one side
                    # — a leading/trailing micro-hesitation — is ~72% of fillers and
                    # over-cuts; matching v2's conservative feel needs both sides.) The
                    # transcript still *refines* it: it rescues fillers where VAD missed
                    # a real word-gap, and demotes VAD "pauses" that are really speech.
                    removable = detached_before and detached_after
                    bkt = bucket(sil_b, sil_a)
                    out.write(json.dumps({
                        "episode": Path(ann).stem, "split": split,
                        "label": r["label_consolidated_vocab"], "start": fs, "end": fe,
                        "duration": round(fe - fs, 3), "sil_before": sil_b, "sil_after": sil_a,
                        "gap_before": round(gb, 3), "gap_after": round(ga, 3),
                        "bucket": bkt, "removable": removable,
                    }) + "\n")
                    counts[split]["removable" if removable else "natural"] += 1
                    flip[(bkt == "isolated", removable)] += 1
                    n += 1

    print(f"wrote {n} fillers ({n_tr} episodes had transcripts) → {out_path}\n")
    for split in ("train", "validation", "test"):
        c = counts.get(split)
        if c:
            tot = sum(c.values())
            print(f"[{split}] {tot}: removable {c['removable']} ({100*c['removable']/tot:.0f}%) | "
                  f"natural {c['natural']} ({100*c['natural']/tot:.0f}%)")
    print("\nv3 vs v2 (isolated-only) label:")
    print(f"  isolated & removable (agree+): {flip[(True, True)]}")
    print(f"  isolated but now natural:      {flip[(True, False)]}")
    print(f"  NOT isolated but now removable (newly rescued boundary/embedded): {flip[(False, True)]}")
    print(f"  not isolated & natural (agree-): {flip[(False, False)]}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--out", default="data/labels_v3")
    a = p.parse_args()
    run(a.data, a.out)


if __name__ == "__main__":
    main()
