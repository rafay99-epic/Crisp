"""Retake detection: find a flubbed take that the speaker immediately repeated.

When you misspeak and say a phrase again, the corrected take is the keeper and the
first attempt is dead weight. In the transcript that shows up as a *repeated run of
words*, back to back in time:

    "the API is slow — the API is fast"      (full restart)
    "so today we're— so today we're going"   (false start / abandoned prefix)
    "the the the parser"                      (single-word stutter)

The rule is the same for all three: find the longest run of words at position `i`
that repeats starting at a later position `j`, and remove everything from the first
take's onset up to the second take's onset — `[start[i], start[j])`. The kept
boundary is always the corrected take's first-word onset, which whisper's DTW gives
us accurately, so the splice lands on a real word start (then the zero-crossing snap
+ fade in `edit` smooth it). This is pure transcript matching — no audio, no model —
so it lives here as a unit-testable function and feeds `build_keep_segments` the same
way fillers and pauses do.

Conservative by design (it cuts automatically): a match needs enough words OR an
immediate single-word stutter, the retake must follow closely in time (rhetorical
repeats far apart survive), and the abandoned span is length-bounded so a phrase that
merely recurs later in the video is never mistaken for a retake.
"""

from .config import (
    RETAKE_MAX_ABANDON, RETAKE_MAX_GAP, RETAKE_MIN_RUN, RETAKE_STUTTER,
    RETAKE_STUTTER_MAX_GAP,
)
from .text import normalize_word


def _common_run(norm, i, j, n):
    """Length of the longest run of equal normalized tokens at `i` and `j`.

    Capped so the first run `[i, i+L)` stays within the abandoned span `[i, j)` —
    the two occurrences must not overlap (which would make a periodic phrase like
    "very very very" report a bogus long match)."""
    L = 0
    while (i + L < j and j + L < n
           and norm[i + L] and norm[i + L] == norm[j + L]):
        L += 1
    return L


def detect_retakes(words, *, min_run=RETAKE_MIN_RUN, max_gap=RETAKE_MAX_GAP,
                   max_abandon=RETAKE_MAX_ABANDON, stutter=RETAKE_STUTTER,
                   stutter_max_gap=RETAKE_STUTTER_MAX_GAP):
    """Spans (start, end) seconds to REMOVE — each a flubbed take the speaker redid.

    `words` is the whisper transcript: a list of ``{"text", "start", "end"}`` in
    order. Returns a list of non-overlapping removal spans; `build_keep_segments`
    merges them with pauses/fillers and clamps to the clip.

    Tunables (defaults in `config`):
      min_run         — words that must match to count as a phrase retake.
      max_gap         — max seconds between the abandoned take's end and the retake's
                        start (a real retake follows promptly).
      max_abandon     — max words in the abandoned take; bounds the search so a phrase
                        that simply recurs later isn't read as a retake.
      stutter         — also catch a single repeated word said back to back…
      stutter_max_gap — …when the two are within this many seconds.
    """
    norm = [normalize_word(w["text"]) for w in words]
    n = len(words)
    spans = []
    i = 0
    while i < n:
        if not norm[i]:
            i += 1
            continue
        best_j, best_len = None, 0
        jmax = min(n, i + 1 + max_abandon)
        for j in range(i + 1, jmax):
            if not norm[j]:
                continue
            run = _common_run(norm, i, j, n)
            if run < 1:
                continue
            # Time from the end of the first matched run to the start of the second:
            # a real retake follows promptly. (Measuring the abandoned take's *own*
            # tail instead would let a phrase recurring much later slip through, since
            # its second occurrence is internally contiguous.)
            gap = words[j]["start"] - words[i + run - 1]["end"]
            is_stutter = j == i + 1 and run == 1
            if stutter and is_stutter:
                need, limit = 1, stutter_max_gap
            else:
                need, limit = min_run, max_gap
            if run >= need and gap <= limit and run > best_len:
                best_j, best_len = j, run
        if best_j is not None:
            spans.append((words[i]["start"], words[best_j]["start"]))
            i = best_j        # resume at the kept take (it may itself be redone again)
        else:
            i += 1
    return spans
