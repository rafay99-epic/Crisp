"""Measure precision AND recall on your OWN footage.

Predictions can't grade themselves — you need ground truth. The honest, low-effort
way is to pick one short window, label every filler in it by ear, and compare the
model's predictions on that window against your labels.

  precision = of the spots the model cut, how many were real fillers?
              (low precision = it's clipping real words — the thing Crisp must avoid)
  recall    = of the real fillers you heard, how many did it catch?
              (low recall = it's leaving ums behind)

Workflow
--------
1) Cut a window you're willing to label (a few minutes is plenty). Writes
   window.wav + an empty labels.json next to it:

     python -m filler_classifier.validate prepare /tmp/test.wav --start 60 --end 240

2) Open window.wav in any player. For EVERY "um/uh" you hear, add its
   [start, end] in seconds (relative to window.wav, which starts at 0) to
   labels.json:

     {"fillers": [[12.3, 12.6], [45.1, 45.8]]}

   Label everything you hear — recall depends on you catching the ones the model
   missed, so label by ear, don't peek at the predictions first.

3) Score the model against your labels:

     python -m filler_classifier.validate score window.wav --labels labels.json --threshold 0.7
"""
from __future__ import annotations

import argparse
import json
import wave
from pathlib import Path

from . import features
from .infer import load_model, predict_intervals
from .labeling import load_intervals


# ------------------------------------------------------------------- prepare

def prepare(src, start, end, out_wav, out_labels):
    with wave.open(str(src), "rb") as w:
        sr, ch, sw, n = (w.getframerate(), w.getnchannels(),
                         w.getsampwidth(), w.getnframes())
        raw = w.readframes(n)

    dur = n / sr
    if start < 0 or start >= dur or (end and end <= start):
        raise SystemExit(f"invalid window [{start}, {end or round(dur, 1)}] for a {dur:.1f}s clip.")

    bpf = ch * sw                                   # bytes per frame
    s = int(start * sr)
    e = int(end * sr) if end else n
    clip = raw[s * bpf:e * bpf]
    with wave.open(str(out_wav), "wb") as o:
        o.setnchannels(ch)
        o.setsampwidth(sw)
        o.setframerate(sr)
        o.writeframes(clip)

    secs = (e - s) / sr
    if not Path(out_labels).exists():
        Path(out_labels).write_text(json.dumps({"fillers": []}, indent=2))
    print(f"wrote {out_wav}  ({secs:.1f}s)  and  {out_labels} (empty template)")
    print(f"→ listen to {out_wav}, add every um/uh as [start, end] to {out_labels}, then run `score`.")


# --------------------------------------------------------------------- score

def _overlap(a, b):
    return a[0] < b[1] and b[0] < a[1]


def _match(pred, gold):
    """Greedy one-to-one overlap match → (true_positives, false_pos list, false_neg list)."""
    used = [False] * len(gold)
    tp, fps = 0, []
    for p in pred:
        hit = next((j for j, g in enumerate(gold) if not used[j] and _overlap(p, g)), -1)
        if hit >= 0:
            used[hit] = True
            tp += 1
        else:
            fps.append(p)
    fns = [g for j, g in enumerate(gold) if not used[j]]
    return tp, fps, fns


def _fmt(iv):
    return ", ".join(f"{a:.2f}-{b:.2f}" for a, b in iv) or "(none)"


def score(window_wav, labels_path, checkpoint, threshold):
    gold = load_intervals(labels_path)              # shared parser: validates bounds
    if not gold:
        raise SystemExit(f"{labels_path} has no fillers yet — label window.wav by ear first.")

    model = load_model(checkpoint)
    wav = features.load_waveform(str(window_wav))
    pred = predict_intervals(model, wav, threshold=threshold)

    tp, fps, fns = _match(pred, gold)
    precision = tp / len(pred) if pred else 0.0
    recall = tp / len(gold) if gold else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0

    print(f"\nthreshold {threshold}  |  {len(gold)} real fillers labeled, {len(pred)} predicted")
    print(f"  precision = {precision:.3f}   ({tp}/{len(pred)} cuts were real fillers)")
    print(f"  recall    = {recall:.3f}   ({tp}/{len(gold)} real fillers were caught)")
    print(f"  F1        = {f1:.3f}")
    print(f"\n  ❌ false positives (cut, but NOT a real filler — check these): {_fmt(fps)}")
    print(f"  🔇 misses (real filler the model skipped):                    {_fmt(fns)}")


# ---------------------------------------------------------------------- cli

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    pp = sub.add_parser("prepare", help="cut a window to label")
    pp.add_argument("audio")
    pp.add_argument("--start", type=float, default=0.0, help="window start (seconds)")
    pp.add_argument("--end", type=float, default=0.0, help="window end (seconds; 0 = to end)")
    pp.add_argument("--out-wav", default="window.wav")
    pp.add_argument("--out-labels", default="labels.json")

    ps = sub.add_parser("score", help="grade the model against your labels")
    ps.add_argument("window_wav")
    ps.add_argument("--labels", default="labels.json")
    ps.add_argument("--checkpoint", default="checkpoints/filler_cnn.pt")
    ps.add_argument("--threshold", type=float, default=0.7)

    a = p.parse_args()
    if a.cmd == "prepare":
        prepare(a.audio, a.start, a.end, a.out_wav, a.out_labels)
    else:
        score(a.window_wav, a.labels, a.checkpoint, a.threshold)


if __name__ == "__main__":
    main()
