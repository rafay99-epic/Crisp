#!/usr/bin/env python3
"""Generate the golden fixtures CrispKit's parity tests assert against.

CrispKit is a port, not a rewrite: every function in it must produce exactly what
`packages/engine` produces today, or the migration silently changes what Crisp cuts.
Proving that with a live dual-runtime test would force Python into CI forever, so
instead this script runs the *Python* implementation over a corpus of inputs and
writes the answers to JSON. The Swift tests then assert against those files, which
means CI needs no Python at all and the fixtures stay reviewable in the diff.

Re-run it whenever the Python side changes, until the Python side is deleted:

    python3 packages/CrispKit/Tools/generate-fixtures.py
"""

import json
import pathlib
import sys
from difflib import SequenceMatcher

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "packages" / "engine"))

from crisp import captions, config, framerate, retake, text, waveform  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[1] / "Tests" / "CrispKitTests" / "Fixtures"


def words(*specs):
    """`("hello", 1.0, 1.4)` triples → the transcript dicts the engine expects."""
    return [{"text": t, "start": s, "end": e} for t, s, e in specs]


def phrase(text_, start, *, word_dur=0.28, gap=0.02):
    """Lay a sentence out on the timeline at a steady speaking rate."""
    out, t = [], start
    for token in text_.split():
        out.append({"text": token, "start": round(t, 4), "end": round(t + word_dur, 4)})
        t += word_dur + gap
    return out, round(t - gap, 4)


# --------------------------------------------------------------------------- fillers

FILLER_TOKENS = [
    # Vocabulary hits.
    "um", "umm", "uh", "uhh", "uhm", "uhmm", "umh", "ummh", "er", "err", "erm", "errm",
    "hm", "hmm", "huh", "hu", "humm", "mm", "mmm", "mhm", "mhmm", "mmhmm",
    "ah", "ahh", "ahem", "aw", "aww", "uh-huh", "mm-hmm",
    # Shape-pattern hits (elongations whisper actually emits).
    "ummmm", "uhhhh", "ummmh", "uhhm", "huhh", "hummm", "hmmmm", "errrm", "aahhh",
    "awwww", "mmmm", "mmhm", "uhhuh", "uh huh", "mm hmm", "mhmmm",
    # Case and punctuation, which normalize() must strip before matching.
    "Um", "UH", "Hmm.", "um,", "—uh—", "(um)", "[uh]", "\"hmm\"", "um…", "'uh'",
    # Real words that must NEVER match.
    "away", "him", "hum", "human", "here", "the", "error", "answer", "awesome",
    "murmur", "mummy", "ahead", "aha", "what", "america", "summer", "hammer",
    "erm.. ", "auto", "moment", "humble", "although", "who", "how",
    # Degenerate input.
    "", " ", "...", "-", "…", "  ,  ",
]

# --------------------------------------------------------------------- token ratios

RATIO_PAIRS = [
    ("were", "we're"), ("colour", "color"), ("open", "opens"), ("the", "they"),
    ("is", "it"), ("in", "on"), ("startup", "enterprise"), ("parser", "parse"),
    ("today", "todays"), ("going", "gone"), ("api", "api"), ("", ""), ("a", ""),
    ("hello", "hello"), ("hello", "olleh"), ("abcdef", "abcdeg"), ("kitten", "sitting"),
    ("interface", "interfaces"), ("record", "recorded"), ("slow", "slowly"),
    ("performance", "performances"), ("database", "databases"), ("value", "values"),
    ("aaaa", "aaab"), ("abab", "baba"), ("xyz", "abc"), ("swift", "swifty"),
]

# ------------------------------------------------------------------------- retakes


def retake_cases():
    """Scenarios that exercise every branch of the decision table."""
    cases = []

    def case(name, ws, **kwargs):
        payload = {"name": name, "words": ws, "options": {}}
        for key, value in kwargs.items():
            payload["options"][key] = value
        cases.append(payload)

    # Full restart, well separated, with a pause anchor.
    first, end1 = phrase("the api is really slow", 0.0)
    second, _ = phrase("the api is really fast", end1 + 0.5)
    case("full-restart-anchored", first + second,
         silences=[[end1, end1 + 0.45]], sensitivity="aggressive")
    case("full-restart-no-silence-data", first + second, sensitivity="aggressive")
    case("full-restart-gentle-anchored", first + second,
         silences=[[end1, end1 + 0.45]], sensitivity="gentle")
    # Same words, but the preset requires a pause and none is present.
    case("full-restart-gentle-unanchored", first + second, silences=[], sensitivity="gentle")
    case("full-restart-balanced-unanchored", first + second, silences=[], sensitivity="balanced")
    case("full-restart-aggressive-unanchored", first + second, silences=[],
         sensitivity="aggressive")

    # A long verbatim repeat with no pause: only the run-length lever admits it.
    long1, lend = phrase("so what i want to show you today is the new parser", 0.0)
    long2, _ = phrase("so what i want to show you today is the new renderer", lend + 0.1)
    case("long-run-no-pause-aggressive", long1 + long2, silences=[], sensitivity="aggressive")
    case("long-run-no-pause-gentle", long1 + long2, silences=[], sensitivity="gentle")

    # Short pause-less repeat: rejected by every preset's run floor.
    s1, s1end = phrase("we ship it", 0.0)
    s2, _ = phrase("we ship it tomorrow", s1end + 0.1)
    case("short-run-no-pause", s1 + s2, silences=[], sensitivity="aggressive")

    # Transcription variance between takes must still align.
    v1, v1end = phrase("were going to colour the interface", 0.0)
    v2, _ = phrase("we're going to color the interfaces", v1end + 0.5)
    case("fuzzy-token-variants", v1 + v2,
         silences=[[v1end, v1end + 0.45]], sensitivity="aggressive")

    # Stutter, both off (default) and on.
    stut = words(("the", 0.0, 0.2), ("the", 0.25, 0.45), ("the", 0.5, 0.7),
                 ("parser", 0.75, 1.2), ("is", 1.25, 1.4), ("fast", 1.45, 1.8))
    case("stutter-off", stut, silences=[], sensitivity="aggressive")
    case("stutter-on", stut, silences=[], sensitivity="aggressive", stutter=True)

    # Periodic phrase: the overlap cap must stop a bogus long match.
    periodic, _ = phrase("very very very very good", 0.0)
    case("periodic-overlap-cap", periodic, silences=[], sensitivity="aggressive")

    # The repeat arrives too late to be a retake.
    late1, late1end = phrase("the api is really slow", 0.0)
    late2, _ = phrase("the api is really slow", late1end + 6.0)
    case("gap-too-large", late1 + late2,
         silences=[[late1end, late1end + 5.9]], sensitivity="aggressive")

    # Chained: the corrected take is itself redone.
    c1, c1end = phrase("let me start over here", 0.0)
    c2, c2end = phrase("let me start over now", c1end + 0.5)
    c3, _ = phrase("let me start over properly", c2end + 0.5)
    case("chained-retakes", c1 + c2 + c3,
         silences=[[c1end, c1end + 0.45], [c2end, c2end + 0.45]], sensitivity="aggressive")

    # Intentional parallel structure that must survive.
    par = []
    t = 0.0
    for item in ("first we build", "then we test", "then we ship"):
        seg, t = phrase(item, t)
        par += seg
        t += 0.5
    case("parallel-structure", par, silences=[], sensitivity="balanced")

    # Empty and single-word input.
    case("empty", [], silences=[], sensitivity="aggressive")
    case("single-word", words(("hello", 0.0, 0.4)), silences=[], sensitivity="aggressive")

    # Abandoned take longer than max_abandon: the search must not reach across it.
    filler_words, fend = phrase("one two three four five six seven eight nine ten "
                                "eleven twelve thirteen fourteen", 0.0)
    tail, _ = phrase("one two three four five", fend + 0.5)
    case("beyond-max-abandon", filler_words + tail,
         silences=[[fend, fend + 0.45]], sensitivity="aggressive")

    return cases


def run_retake(case):
    policy = config.RETAKE_SENSITIVITY[case["options"].get("sensitivity", "aggressive")]
    silences = case["options"].get("silences")
    spans = retake.detect_retakes(
        case["words"],
        min_run=policy["min_run"],
        require_pause=policy["require_pause"],
        min_run_no_pause=policy["min_run_no_pause"],
        sem_min=policy["sem_min"],
        stutter=case["options"].get("stutter", config.RETAKE_STUTTER),
        silences=[tuple(s) for s in silences] if silences is not None else None,
    )
    return [[round(a, 6), round(b, 6)] for a, b in spans]


# ---------------------------------------------------------------------- frame rate

FPS_CASES = [
    ("auto", 0, "30/1", "30/1"),
    ("auto", 0, "60/1", "48.2/1"),
    ("auto", 0, "30000/1001", "30000/1001"),
    ("auto", 0, "60/1", "30/1"),
    ("auto", 24, "60/1", "30/1"),
    ("auto", 0, "N/A", "30/1"),
    ("auto", 0, "", ""),
    ("auto", 0, "0/0", "30/1"),
    ("auto", 0, "1000/1", "30/1"),
    ("auto", 0, "30/1", "0/0"),
    ("passthrough", 30, "60/1", "30/1"),
    ("constant", 30, "60/1", "30/1"),
    ("constant", 0, "60/1", "30/1"),
    ("constant", 29.97, "60/1", "30/1"),
    ("constant", 500, "60/1", "30/1"),
    ("auto", 0, "25", "24.9"),
]

# ------------------------------------------------------------------------ captions


def caption_cases():
    cases = []

    long_line = ("this is a fairly long sentence that will certainly need to wrap onto "
                 "a second line and then start a brand new cue entirely")
    ws, _ = phrase(long_line, 0.0, word_dur=0.22, gap=0.03)
    cases.append({"name": "wrapping-and-splitting", "words": ws,
                  "keep": [[0.0, 12.0]]})

    ws2 = words(("Hello", 0.0, 0.4), ("there.", 0.45, 0.9),
                ("um", 1.0, 1.3), ("How", 2.0, 2.3), ("are", 2.35, 2.6),
                ("you?", 2.65, 3.0), ("Fine.", 4.2, 4.7))
    cases.append({"name": "sentences-fillers-and-gaps", "words": ws2,
                  "keep": [[0.0, 1.0], [1.9, 5.0]]})

    ws3 = words(("a", 0.0, 0.1), ("b", 0.15, 0.25), ("c", 0.3, 0.4))
    cases.append({"name": "short-cue-stretching", "words": ws3, "keep": [[0.0, 1.0]]})

    ws4 = words(("straddles", 0.5, 1.5), ("gap", 2.0, 2.4), ("kept", 3.1, 3.5))
    cases.append({"name": "straddling-and-removed", "words": ws4,
                  "keep": [[0.0, 1.0], [3.0, 4.0]]})

    ws5 = words(("<b>markup</b>", 0.0, 0.5), ("A&B", 0.6, 1.0))
    cases.append({"name": "vtt-escaping", "words": ws5, "keep": [[0.0, 2.0]]})

    cases.append({"name": "empty", "words": [], "keep": [[0.0, 1.0]]})
    return cases


def run_captions(case):
    keep = [tuple(k) for k in case["keep"]]
    cues = captions.build_captions(case["words"], keep)
    return {
        "cues": [{"start": round(c["start"], 6), "end": round(c["end"], 6),
                  "lines": c["lines"]} for c in cues],
        "srt": captions.to_srt(cues),
        "vtt": captions.to_vtt(cues),
    }


# ------------------------------------------------------------------------ waveform

def waveform_cases():
    import math
    cases = []
    sine = [int(20000 * math.sin(i / 12.0)) for i in range(1000)]
    cases.append({"name": "sine", "samples": sine, "buckets": 16})
    ramp = [int(-32768 + (65535 * i / 499)) for i in range(500)]
    cases.append({"name": "ramp-full-scale", "samples": ramp, "buckets": 10})
    cases.append({"name": "silence", "samples": [0] * 300, "buckets": 8})
    cases.append({"name": "fewer-samples-than-buckets", "samples": [100, -200, 300],
                  "buckets": 8})
    cases.append({"name": "empty", "samples": [], "buckets": 8})
    # Int16.min has no positive counterpart; the peak math must not overflow on it.
    cases.append({"name": "int16-min", "samples": [-32768, 0, 32767], "buckets": 3})
    return cases


REMOVED_CASES = [
    {"name": "simple", "buckets": 10, "duration": 10.0, "keep": [[0.0, 5.0]]},
    {"name": "two-segments", "buckets": 12, "duration": 6.0,
     "keep": [[0.0, 1.0], [3.0, 4.5]]},
    {"name": "nothing-kept", "buckets": 5, "duration": 5.0, "keep": []},
    {"name": "zero-duration", "buckets": 5, "duration": 0.0, "keep": [[0.0, 1.0]]},
]


# ----------------------------------------------------------------------------- main

def main():
    OUT.mkdir(parents=True, exist_ok=True)

    write("fillers.json", [{"token": t, "normalized": text.normalize_word(t),
                            "isFiller": text.is_filler(t)} for t in FILLER_TOKENS])

    write("ratios.json", [{"a": a, "b": b, "ratio": SequenceMatcher(None, a, b).ratio()}
                          for a, b in RATIO_PAIRS])

    write("retakes.json", [dict(case, expected=run_retake(case)) for case in retake_cases()])

    write("framerate.json", [
        {"mode": mode, "requestedFPS": fps, "base": r, "average": avg,
         "expected": framerate.resolve_target_fps(mode, fps, r, avg)}
        for mode, fps, r, avg in FPS_CASES
    ])

    write("captions.json", [dict(case, expected=run_captions(case))
                            for case in caption_cases()])

    write("waveform.json", {
        "peaks": [dict(case, expected=waveform._peaks_from_samples(case["samples"],
                                                                   case["buckets"]))
                  for case in waveform_cases()],
        "removed": [dict(case,
                         expected=waveform._removed_flags(case["buckets"],
                                                          case["duration"],
                                                          [tuple(k) for k in case["keep"]]))
                    for case in REMOVED_CASES],
    })

    write("config.json", {
        "maxPause": config.DEFAULT_MAX_PAUSE,
        "noiseDB": config.DEFAULT_NOISE_DB,
        "keepPause": config.DEFAULT_KEEP_PAUSE,
        "minKeep": config.MIN_KEEP,
        "tightPause": config.DEFAULT_TIGHT_PAUSE,
        "fadeMS": config.DEFAULT_FADE_MS,
        "crossfadeMS": config.DEFAULT_CROSSFADE_MS,
        "snapMS": config.DEFAULT_SNAP_MS,
        "audioBitrateKbps": config.DEFAULT_AUDIO_BITRATE,
        "fillerMinSolo": config.FILLER_MIN_SOLO,
        "fillerPausePad": config.FILLER_PAUSE_PAD,
        "retakeMaxGap": config.RETAKE_MAX_GAP,
        "retakeMaxAbandon": config.RETAKE_MAX_ABANDON,
        "retakeTokenSimilarity": config.RETAKE_TOKEN_SIM,
        "retakeAnchorPause": config.RETAKE_ANCHOR_PAUSE,
        "retakePausePad": config.RETAKE_PAUSE_PAD,
        "retakeStutterMaxGap": config.RETAKE_STUTTER_MAX_GAP,
        "defaultSensitivity": config.DEFAULT_RETAKE_SENSITIVITY,
        "sensitivities": config.RETAKE_SENSITIVITY,
        "fillerVocabulary": sorted(config.DEFAULT_FILLERS),
        "captions": {
            "maxCharsPerLine": captions.MAX_CHARS_PER_LINE,
            "maxLines": captions.MAX_LINES,
            "minCueDur": captions.MIN_CUE_DUR,
            "maxCueDur": captions.MAX_CUE_DUR,
            "cueSplitGap": captions.CUE_SPLIT_GAP,
            "minGap": captions.MIN_GAP,
        },
        "framerate": {
            "vfrRelTol": framerate.VFR_REL_TOL,
            "maxPlausibleFPS": framerate.MAX_PLAUSIBLE_FPS,
        },
    })


def write(name, payload):
    path = OUT / name
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
