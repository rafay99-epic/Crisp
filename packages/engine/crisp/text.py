"""Filler-word matching against the vocabulary in `config`."""

from .config import DEFAULT_FILLERS, FILLER_PATTERNS


def normalize_word(text: str) -> str:
    return text.strip().strip(".,!?;:\"'()[]…-–—").lower()


def is_filler(text: str) -> bool:
    """True if `text` is a hesitation sound — um / uh / hmm / aww / huh and the
    many elongated or variant spellings whisper produces (ummh, hummm, errr,
    mm-hmm…). Matching is anchored (whole token only), so ordinary words such as
    "away", "him", "human", or the verb "hum" are never treated as fillers."""
    word = normalize_word(text)
    if not word:
        return False
    if word in DEFAULT_FILLERS:
        return True
    return any(pattern.fullmatch(word) for pattern in FILLER_PATTERNS)
