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

DEFAULT_MAX_PAUSE = 0.6       # cut silences longer than this (seconds)
DEFAULT_NOISE_DB = -30        # audio below this loudness (dB) counts as silence
DEFAULT_KEEP_PAUSE = 0.15     # breathing room left around each cut (seconds)
MIN_KEEP = 0.05               # drop kept fragments shorter than this (seconds)

# Re-encode settings (see crisp.encode). Default to Apple hardware HEVC: every
# Apple-Silicon Mac (all Crisp runs on) has a HEVC media engine, so it's the fast
# default. If a hardware encode fails (e.g. a macOS VM with no media engine) the
# pipeline falls back to software automatically.
DEFAULT_VIDEO_CODEC = "hevc"  # h264 | hevc
DEFAULT_HARDWARE = True        # Apple VideoToolbox (faster; software is better per-size)
DEFAULT_QUALITY = "high"      # maximum | high | balanced | smaller
DEFAULT_AUDIO_CODEC = "aac"   # aac | opus
DEFAULT_AUDIO_BITRATE = 192   # kbps

# The engine dir is the package's parent (…/engine/crisp → …/engine).
HERE = Path(__file__).resolve().parent.parent
DEFAULT_MODEL = HERE / "models" / "ggml-base.en.bin"
