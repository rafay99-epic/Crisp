"""Phase 0 — validate the VAD-derived labels against Crisp's real pipeline.

`derive_labels.py` bucketed each filler from PodcastFillers' VAD (cheap, our own
signal). This cross-checks those buckets against what the *shipped engine* actually
sees, on a subset of full episodes:

  • silencedetect (always) — the engine's real pause detector (ffmpeg, noise/dB based,
    a different method than VAD). If our "isolated → REMOVABLE" fillers sit next to an
    engine-detected pause far more often than "embedded → NATURAL" ones, our cheap
    labels agree with the thing that actually drives cuts → we can trust them.
  • whisper (optional, --whisper) — runs the same whisper step the engine uses and
    checks it independently calls the spot a filler word, and shows the words around
    it (the language context VAD can't see). Slow, so default to a couple episodes.

This reuses the engine's own `crisp` package (the exact code that ships), so the
validation matches production behavior rather than a re-implementation.

    python -m filler_classifier.v2.validate_labels --limit 8                 # fast (pauses)
    python -m filler_classifier.v2.validate_labels --whisper --limit 2       # + whisper
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "apps" / "desktop" / "Resources" / "engine"))
from crisp.config import DEFAULT_MAX_PAUSE, DEFAULT_NOISE_DB           # noqa: E402
from crisp.detect import detect_silences, extract_audio, transcribe   # noqa: E402
from crisp.text import is_filler                                      # noqa: E402

GAP = 0.35          # a pause within this of a filler edge counts as "adjacent"
WHISPER_TOL = 0.35  # a whisper filler word within this of an annotation = a match
_noop = lambda *a, **k: None

WHISPER_BIN = "/Applications/Crisp Dev.app/Contents/Resources/engine/bin/whisper-cli"
WHISPER_MODEL = str(Path.home() / ".crisp-dev" / "models" / "ggml-base.en.bin")


def load_fillers(labels_path: str):
    """Group derived filler records by episode."""
    by_ep = defaultdict(list)
    with open(labels_path) as f:
        for line in f:
            r = json.loads(line)
            by_ep[(r["split"], r["episode"])].append(r)
    return by_ep


def episode_mp3(data_dir: Path, split: str, episode: str) -> Path | None:
    p = data_dir / "audio" / "episode_mp3" / split / f"{episode}.mp3"
    return p if p.exists() else None


def adjacent_pause(silences, start, end) -> bool:
    """Any engine-detected silence within GAP of the filler edges?"""
    for s0, s1 in silences:
        if s1 >= start - GAP and s0 <= end + GAP:
            return True
    return False


def run(data_dir, labels_path, limit, split, use_whisper, whisper_model=WHISPER_MODEL):
    data_dir = Path(data_dir)
    by_ep = load_fillers(labels_path)
    # Only episodes whose audio is actually on disk (the download is partial), so the
    # limit isn't spent on skips.
    present = [k for k in by_ep if k[0] == split and episode_mp3(data_dir, k[0], k[1])]
    eps = sorted(present)[:limit]
    if not eps:
        raise SystemExit(f"No '{split}' episodes with audio under {data_dir}. "
                         f"({len(by_ep)} episodes labeled, but their mp3s aren't downloaded.)")
    print(f"{len(present)} '{split}' episodes have audio; validating {len(eps)}.")

    pause_hits = defaultdict(Counter)     # bucket -> {adjacent: n, total: n}
    whisper_hits = defaultdict(Counter)   # bucket -> {match: n, total: n}
    done = 0
    with tempfile.TemporaryDirectory() as tmp:
        for (sp, ep) in eps:
            mp3 = episode_mp3(data_dir, sp, ep)
            if not mp3:
                print(f"  (skip, no mp3) {ep}")
                continue
            wav = Path(tmp) / "ep.wav"
            extract_audio(mp3, wav, _noop)
            silences = detect_silences(wav, DEFAULT_NOISE_DB, DEFAULT_MAX_PAUSE, _noop)

            words = []
            if use_whisper:
                words = transcribe(WHISPER_BIN, whisper_model, wav, Path(tmp) / "out", _noop, _noop)
                fillers_w = [(w["start"], w["end"]) for w in words if is_filler(w["text"])]

            for r in by_ep[(sp, ep)]:
                b = r["bucket"]
                pause_hits[b]["total"] += 1
                if adjacent_pause(silences, r["start"], r["end"]):
                    pause_hits[b]["adjacent"] += 1
                if use_whisper:
                    whisper_hits[b]["total"] += 1
                    if any(abs(fs - r["start"]) <= WHISPER_TOL or fs <= r["end"] <= fe + WHISPER_TOL
                           for fs, fe in fillers_w):
                        whisper_hits[b]["match"] += 1
            done += 1
            # whisper_words shows whisper's TOTAL transcription: if it's in the
            # thousands but whisper_fillers is tiny, whisper is dropping fillers (low
            # recall) — a property of whisper, not a bug or a bad label.
            print(f"  [{done}/{len(eps)}] {ep[:50]:50}  pauses={len(silences)}"
                  + (f"  whisper_words={len(words)} whisper_fillers={len(fillers_w)}"
                     if use_whisper else ""))

    print(f"\n=== pause-adjacency by bucket  ({done} episodes, {split}) ===")
    print("(does the engine's real pause detector agree a filler is at a pause?)")
    for b in ("isolated", "boundary", "embedded"):
        c = pause_hits.get(b)
        if c and c["total"]:
            print(f"  {b:9} {c['adjacent']:5}/{c['total']:<5} "
                  f"({100*c['adjacent']/c['total']:4.1f}% next to an engine pause)")
    if use_whisper:
        print("\n=== whisper agreement by bucket ===")
        print("(does whisper independently transcribe a filler word at the spot?)")
        for b in ("isolated", "boundary", "embedded"):
            c = whisper_hits.get(b)
            if c and c["total"]:
                print(f"  {b:9} {c['match']:5}/{c['total']:<5} "
                      f"({100*c['match']/c['total']:4.1f}% confirmed by whisper)")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", default="data/PodcastFillers")
    p.add_argument("--labels", default="data/labels_v2/fillers.jsonl")
    p.add_argument("--limit", type=int, default=8, help="episodes to validate")
    p.add_argument("--split", default="train")
    p.add_argument("--whisper", action="store_true", help="also run whisper (slow)")
    p.add_argument("--whisper-model", default=WHISPER_MODEL,
                   help="ggml whisper model (default base.en; try the large turbo for recall)")
    a = p.parse_args()
    run(a.data, a.labels, a.limit, a.split, a.whisper, a.whisper_model)


if __name__ == "__main__":
    main()
