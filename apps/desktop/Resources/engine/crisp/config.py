"""Tunable defaults and the filler-word vocabulary.

All values here are overridable from the CLI / `clean_video()` arguments.
"""

import re
from pathlib import Path

# Words treated as "fillers" and removed (see crisp.text.is_filler). Compared
# after lower-casing and stripping punctuation. Kept to non-words / hesitations
# so we don't cut real speech. This explicit set covers the common short forms;
# the shape patterns below catch the endless elongated/variant spellings whisper
# emits (ummh, hummm, errr, mm-hmm…). Edit either to taste.
DEFAULT_FILLERS = {
    "um", "umm", "uh", "uhh", "uhm", "uhmm", "umh", "ummh",
    "er", "err", "erm", "errm",
    "hm", "hmm", "huh", "hu", "humm",
    "mm", "mmm", "mhm", "mhmm", "mmhmm",
    "ah", "ahh", "ahem", "aw", "aww",
    "uh-huh", "mm-hmm",
}

# Hesitation sounds show up in countless elongated/variant spellings. Rather than
# enumerate them all, match their *shape*. These are full-match patterns (see
# crisp.text.is_filler), so they only fire on a token that is ENTIRELY a
# hesitation — real words like "away", "him", "human", or the verb "hum" never
# match.
FILLER_PATTERNS = tuple(re.compile(p) for p in (
    r"u+m+h*",        # um, umm, ummm, umh, ummh, ummmh
    r"u+h+m*",        # uh, uhh, uhhh, uhm, uhmm
    r"h+u+h+",        # huh, huhh
    r"h+u+m{2,}",     # humm, hummm  (≥2 m's so the verb "hum" is left alone)
    r"h+m+",          # hm, hmm, hmmm
    r"e+r+m*",        # er, err, erm, errm, errrm
    r"a+h+",          # ah, ahh, aah, ahhh
    r"a+w+",          # aw, aww, awww
    r"m{2,}",         # mm, mmm
    r"m+h+m*",        # mhm, mmhm, mhmm
    r"u+h+[-\s]?h+u+h+",  # uh-huh, uhhuh
    r"m+h?[-\s]?h+m+",    # mm-hmm, mhmm
))

DEFAULT_BACKUP = True         # copy the original aside before cutting (safety net)
DEFAULT_MAX_PAUSE = 0.6       # cut silences longer than this (seconds)
DEFAULT_NOISE_DB = -30        # audio below this loudness (dB) counts as silence
DEFAULT_KEEP_PAUSE = 0.15     # breathing room left around each cut (seconds)
MIN_KEEP = 0.05               # drop kept fragments shorter than this (seconds)

# Cut smoothing (see crisp.edit). A hard splice clicks because the audio waveform
# jumps from one amplitude to another at the join; these three knobs soften it.
DEFAULT_FADE_MS = 10          # audio fade-in/out on each kept segment so joins don't click (ms; 0 = off)
DEFAULT_CROSSFADE_MS = 0      # >0 dissolves consecutive segments (matched video xfade + audio acrossfade) instead of hard cuts (ms)
DEFAULT_SNAP_MS = 12          # snap each cut boundary to the nearest zero-crossing within ±this window (ms; 0 = off)

# Re-encode settings (see crisp.encode). Default to Apple hardware HEVC: every
# Apple-Silicon Mac (all Crisp runs on) has a HEVC media engine, so it's the fast
# default. If a hardware encode fails (e.g. a macOS VM with no media engine) the
# pipeline falls back to software automatically.
DEFAULT_VIDEO_CODEC = "hevc"  # h264 | hevc
DEFAULT_HARDWARE = True        # Apple VideoToolbox (faster; software is better per-size)
DEFAULT_QUALITY = "high"      # maximum | high | balanced | smaller
DEFAULT_AUDIO_CODEC = "aac"   # aac | opus
DEFAULT_AUDIO_BITRATE = 192   # kbps
DEFAULT_CONTAINER = "auto"    # auto (match input) | mp4 | mkv | mov | m4v | ts | webm
DEFAULT_FILLER_BACKEND = "whisper"  # whisper | coreml (fast on-device classifier)

# Retake removal (see crisp.retake): when you misspeak and immediately say a phrase
# again, the first attempt is a repeated run of words in the transcript — cut it and
# keep the corrected take. Conservative defaults so it can run automatically. Needs a
# real whisper transcript (the coreml filler backend doesn't transcribe).
DEFAULT_REMOVE_RETAKES = True
# Each sensitivity preset is a full policy, not just a word count:
#   min_run          — matched words needed to treat a pause-anchored repeat as a redo.
#   require_pause    — must a SHORT repeat begin right after a silence? Gentle/balanced
#                      keep this. Aggressive relaxes it (see min_run_no_pause).
#   min_run_no_pause — the lever for natural mid-sentence restarts (no pause, no "um"):
#                      a verbatim repeat THIS long is accepted even without a pause,
#                      because parallel structure rarely repeats this many words. This
#                      — not the embedding — is the load-bearing precision signal for
#                      pause-less detection. None ⇒ a pause is always required (gentle).
#   sem_min          — semantic-similarity bar (corrected vs. flubbed take, via
#                      crisp-embed) that can RESCUE a shorter pause-less repeat. Set
#                      high on purpose: Apple's on-device sentence embedding is noisy on
#                      short phrases (it scores a real redo and a parallel list alike),
#                      so it never vetoes a word+pause match — every candidate's score
#                      is just logged, to gather real-footage data on whether a stronger
#                      embedding/LLM judge is worth it later. (See retake-research.md.)
RETAKE_SENSITIVITY = {
    "gentle":     {"min_run": 5, "require_pause": True,  "min_run_no_pause": None, "sem_min": 0.78},
    "balanced":   {"min_run": 4, "require_pause": True,  "min_run_no_pause": 7,    "sem_min": 0.78},
    "aggressive": {"min_run": 3, "require_pause": False, "min_run_no_pause": 5,    "sem_min": 0.70},
}
# Default is AGGRESSIVE: validated on real talking-head footage to catch the natural
# mid-sentence restarts most speakers actually make (no pause, no marker) while the
# run-length lever holds precision. gentle/balanced stay available for list-heavy
# content where a shorter run can over-cut intentional parallel structure.
DEFAULT_RETAKE_SENSITIVITY = "aggressive"      # gentle | balanced | aggressive
# Bare `detect_retakes()` defaults mirror the WHOLE default preset (not just min_run),
# so a direct library call behaves exactly like the app's default rather than a hybrid
# of aggressive's run floor and gentle's pause policy.
_DEFAULT_RETAKE_POLICY = RETAKE_SENSITIVITY[DEFAULT_RETAKE_SENSITIVITY]
RETAKE_MIN_RUN = _DEFAULT_RETAKE_POLICY["min_run"]
RETAKE_REQUIRE_PAUSE = _DEFAULT_RETAKE_POLICY["require_pause"]
RETAKE_MIN_RUN_NO_PAUSE = _DEFAULT_RETAKE_POLICY["min_run_no_pause"]
RETAKE_SEM_MIN = _DEFAULT_RETAKE_POLICY["sem_min"]
# Back-compat: the per-name min-run map other callers still read.
RETAKE_SENSITIVITY_MIN_RUN = {k: v["min_run"] for k, v in RETAKE_SENSITIVITY.items()}
RETAKE_MAX_GAP = 2.0        # seconds: a retake follows its flubbed take within this gap
RETAKE_MAX_ABANDON = 12     # words: longest abandoned take to look across (bounds the search)
# Two takes of the same line rarely transcribe identically — whisper varies
# contractions, spelling and word forms between takes ("we're"/"were",
# "colour"/"color", "open"/"opens"). Matching only exact tokens silently misses
# those retakes, so a run also counts tokens whose similarity (difflib ratio) clears
# this bar as "the same word". Kept high — and short tokens still require an exact
# match — so genuinely different words ("startup"/"enterprise", "the"/"they") never
# merge: the precision guard against intentional parallel structure stays intact.
RETAKE_TOKEN_SIM = 0.85
# (RETAKE_REQUIRE_PAUSE / RETAKE_MIN_RUN_NO_PAUSE are derived from the default preset
# above — a real retake is normally preceded by a pause, which gentle/balanced require;
# aggressive relaxes it and leans on the run-length floor instead.)
# Detect anchor pauses at this SHORT silence threshold — separate from the cut threshold
# (DEFAULT_MAX_PAUSE) — because a redo pause is brief (~0.3s); the longer cut threshold
# misses it entirely.
RETAKE_ANCHOR_PAUSE = 0.3
RETAKE_PAUSE_PAD = 0.35     # seconds: how close the retake onset must sit to a silence edge
# Single-word stutter ("the the the") trimming is OFF by default: a back-to-back word
# repeat is ambiguous — intentional emphasis ("very very", "no no") looks identical to a
# stumble, so cutting it risks deleting real speech. Opt in per-call when desired.
RETAKE_STUTTER = False
RETAKE_STUTTER_MAX_GAP = 1.0  # seconds: how close the repeated single word must be (when enabled)
# Silence-gating for the coreml backend: only cut a detected filler if it's clearly
# long (a deliberate "uhh") OR sits right at a pause boundary. Brief fillers embedded
# mid-speech are kept — cutting those breaks sentences and looks rough.
FILLER_MIN_SOLO = 0.5    # seconds: cut a non-pause filler only if at least this long
FILLER_PAUSE_PAD = 0.2   # seconds: a filler within this of a silence edge counts as "at a pause"

# The engine dir is the package's parent (…/engine/crisp → …/engine).
HERE = Path(__file__).resolve().parent.parent
DEFAULT_MODEL = HERE / "models" / "ggml-base.en.bin"
