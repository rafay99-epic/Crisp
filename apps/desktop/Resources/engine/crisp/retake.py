"""Retake detection: find a flubbed take that the speaker immediately repeated.

When you misspeak and say a phrase again, the corrected take is the keeper and the
first attempt is dead weight. In the transcript that shows up as a *repeated run of
words*, back to back in time:

    "the API is slow — the API is fast"      (full restart)
    "so today we're— so today we're going"   (false start / abandoned prefix)
    "the the the parser"                      (single-word stutter)

The rule is the same for all three: find the longest run of words at position `i`
that repeats starting at a later position `j`, and remove everything from the first
take's onset up to the second take's onset — `[start[i], start[j])`. The run match
is *fuzzy* at the token level — two takes of the same line rarely transcribe
identically (whisper varies contractions, spelling and word forms), so near-equal
tokens still count, while genuinely different words don't (see `_tokens_match`). The kept
boundary is always the corrected take's first-word onset, which whisper's DTW gives
us accurately, so the splice lands on a real word start (then the zero-crossing snap
+ fade in `edit` smooth it). This is pure transcript matching — no audio, no model —
so it lives here as a unit-testable function and feeds `build_keep_segments` the same
way fillers and pauses do.

Conservative by design (it cuts automatically): a match needs enough words OR an
immediate single-word stutter, the retake must follow closely in time (rhetorical
repeats far apart survive), and the abandoned span is length-bounded so a phrase that
merely recurs later in the video is never mistaken for a retake.

Two signals lift it past pure word-matching (each optional, so the bare library call
and the unit tests still run with neither):

  * **Pause anchor** — the corrected take must begin right after a detected silence.
    The strongest precision signal, but it MISSES natural mid-sentence restarts that
    have no pause. Gentle/balanced keep it as a hard gate; aggressive drops it.
  * **Semantic gate** (`judge`) — a callable scoring how alike the flubbed take and
    the corrected take are in *meaning* (Apple NL embeddings, via `crisp-embed`). It
    confirms a redo when the pause anchor is off, so aggressive can catch pause-less
    restarts without the false positives that simply dropping the anchor would cause.
    Without a judge we never drop the anchor — it's the only precision signal left.

Every candidate's signals and the accept/skip decision are logged (when a `logger`
is supplied) so the thresholds can be tuned against real footage.
"""

import bisect
from difflib import SequenceMatcher

from .config import (
    RETAKE_MAX_ABANDON, RETAKE_MAX_GAP, RETAKE_MIN_RUN, RETAKE_MIN_RUN_NO_PAUSE,
    RETAKE_PAUSE_PAD, RETAKE_REQUIRE_PAUSE, RETAKE_SEM_MIN, RETAKE_STUTTER,
    RETAKE_STUTTER_MAX_GAP, RETAKE_TOKEN_SIM,
)
from .text import normalize_word


def _join(words):
    """Readable text of a word slice — for the semantic judge and the debug log."""
    return " ".join(w["text"].strip() for w in words).strip()


def _decide(anchored, has_pause, run, min_run_no_pause, require_pause, sim, sem_min):
    """Accept/skip a candidate retake, with a short reason for the log.

    `anchored`        — was silence data supplied (so `has_pause` is meaningful)?
    `has_pause`       — does the corrected take begin right after a silence?
    `run`             — matched-word run length of this candidate.
    `min_run_no_pause`— accept a PAUSE-LESS repeat once the run reaches this; None ⇒
                        a pause is always required. The load-bearing precision signal
                        for mid-sentence restarts (a long verbatim repeat is hard to
                        produce by accident).
    `require_pause`   — whether a short pause-less repeat is rejected outright (only
                        changes the log reason — the thresholds above do the real work).
    `sim`             — semantic similarity of flubbed vs. corrected take, or None when
                        not scored. A high value can RESCUE a shorter pause-less repeat;
                        it never vetoes (Apple's short-phrase embedding is too noisy —
                        it scores real redos and parallel lists alike, so a low score is
                        not evidence of a non-redo).
    `sem_min`         — similarity bar for that rescue (set high on purpose).
    """
    if has_pause:
        return True, f"pause(sim={sim:.2f})" if sim is not None else "pause"
    if not anchored:
        return True, "no-silence-data"        # bare CLI / library call: run+gap only
    # No pause before the redo. Only presets that OPT IN to a pause-less path
    # (`min_run_no_pause` set) may cut here — so a pause-required preset like gentle
    # stays pause-required even when a judge is available. A long-enough verbatim
    # repeat is strong evidence of a restart; a very strong semantic match can rescue
    # a shorter one.
    if min_run_no_pause is not None:
        if run >= min_run_no_pause:
            return True, f"long-run-no-pause({run}>={min_run_no_pause})"
        if sim is not None and sim >= sem_min:
            return True, f"semantic-no-pause({sim:.2f}>={sem_min:.2f})"
    return False, ("no-pause" if require_pause else f"short-run-no-pause(run={run})")

# Tokens shorter than this must match exactly: a similarity ratio is unreliable on
# short function words — "the"/"they", "is"/"it", "in"/"on" all clear a high bar yet
# are different words, and merging them would forge spurious runs.
_FUZZY_MIN_LEN = 4


def _tokens_match(a, b, token_sim):
    """True if two normalized tokens are the same word, tolerating the minor spelling
    variance whisper emits between takes ("we're"/"were", "colour"/"color",
    "open"/"opens"). Empty tokens (punctuation) never match; short tokens require an
    exact match (see `_FUZZY_MIN_LEN`); otherwise a difflib ratio at or above
    `token_sim` counts."""
    if not a or not b:
        return False
    if a == b:
        return True
    if min(len(a), len(b)) < _FUZZY_MIN_LEN:
        return False
    return SequenceMatcher(None, a, b).ratio() >= token_sim


def _common_run(norm, i, j, n, token_sim):
    """Length of the longest run of matching normalized tokens at `i` and `j`.

    Tokens match fuzzily (`_tokens_match`) so transcription variants between takes
    still align. Capped so the first run `[i, i+L)` stays within the abandoned span
    `[i, j)` — the two occurrences must not overlap (which would make a periodic
    phrase like "very very very" report a bogus long match)."""
    L = 0
    while (i + L < j and j + L < n
           and _tokens_match(norm[i + L], norm[j + L], token_sim)):
        L += 1
    return L


def detect_retakes(words, *, min_run=RETAKE_MIN_RUN, max_gap=RETAKE_MAX_GAP,
                   max_abandon=RETAKE_MAX_ABANDON, stutter=RETAKE_STUTTER,
                   stutter_max_gap=RETAKE_STUTTER_MAX_GAP, silences=None,
                   require_pause=RETAKE_REQUIRE_PAUSE, pause_pad=RETAKE_PAUSE_PAD,
                   token_sim=RETAKE_TOKEN_SIM, min_run_no_pause=RETAKE_MIN_RUN_NO_PAUSE,
                   judge=None, sem_min=RETAKE_SEM_MIN, logger=None):
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
      silences        — list of (start, end) pause spans (from silencedetect). Enables
                        the pause anchor (the corrected take must begin right after a
                        silence). The bare library call may omit it.
      require_pause   — reject a SHORT pause-less repeat outright (gentle/balanced).
                        Aggressive passes False; the run-length lever below is what
                        actually admits pause-less restarts (no-op when `silences` is
                        None — the bare call has no pause data).
      pause_pad       — how close (seconds) the retake onset must sit to a silence edge.
      token_sim       — minimum difflib similarity for two tokens to count as the same
                        word, so transcription variants between takes still align
                        ("we're"/"were"); short tokens still need an exact match.
      min_run_no_pause— accept a pause-less verbatim repeat once its run reaches this
                        (the precision lever for mid-sentence restarts). None ⇒ a pause
                        is always required (what gentle passes). Bare-call default mirrors
                        the default preset (see config.RETAKE_MIN_RUN_NO_PAUSE).
      judge           — optional `judge(flubbed_text, corrected_text) -> float|None`
                        scoring how alike the two takes are in meaning (0–1). A high
                        score can rescue a shorter pause-less repeat; it NEVER vetoes
                        (the embedding is too noisy on short phrases). None ⇒ off.
      sem_min         — similarity bar for that rescue.
      logger          — optional EngineLogger; every candidate's signals + decision are
                        logged at debug for tuning.
    """
    norm = [normalize_word(w["text"]) for w in words]
    n = len(words)
    anchored = silences is not None
    # A pause is mandatory (so selection skips un-anchored repeats, as before) unless
    # the preset opted into a pause-less path via `min_run_no_pause`. The judge does NOT
    # relax this — a pause-required preset like gentle stays pause-required even with the
    # semantic gate available (the judge can only ever add precision, never remove it).
    pause_is_mandatory = require_pause and min_run_no_pause is None
    sil_ends = sorted(se for _s, se in silences) if anchored else []

    def begins_after_pause(onset):
        # Is there a silence whose END lands within ±pause_pad of this word onset?
        k = bisect.bisect_left(sil_ends, onset - pause_pad)
        return k < len(sil_ends) and sil_ends[k] <= onset + pause_pad

    spans = []
    i = 0
    while i < n:
        if not norm[i]:
            i += 1
            continue
        best_j, best_len, best_pause = None, 0, False
        jmax = min(n, i + 1 + max_abandon)
        for j in range(i + 1, jmax):
            if not norm[j]:
                continue
            run = _common_run(norm, i, j, n, token_sim)
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
            if run < need or gap > limit:
                continue
            has_pause = anchored and begins_after_pause(words[j]["start"])
            # When a pause is mandatory (gentle / bare call), an un-anchored repeat
            # can't win — skip it during selection so behaviour is unchanged. When a
            # pause-less path exists, consider it and let `_decide` rule below.
            if pause_is_mandatory and anchored and not has_pause:
                continue
            if run > best_len:
                best_j, best_len, best_pause = j, run, has_pause

        if best_j is None:
            i += 1
            continue

        # Score the best candidate's meaning (skip single-word stutters — embeddings
        # need a phrase) and make the final call.
        sim = None
        if judge is not None and best_len >= 2:
            flubbed = _join(words[i:best_j])
            corrected = _join(words[best_j:best_j + (best_j - i)])
            sim = judge(flubbed, corrected)
        accept, reason = _decide(anchored, best_pause, best_len, min_run_no_pause,
                                 require_pause, sim, sem_min)
        if logger is not None:
            simtxt = f"{sim:.3f}" if sim is not None else "—"
            logger.debug(
                f"retake @{words[i]['start']:.2f}s run={best_len} "
                f"pause={'Y' if best_pause else 'N'} sim={simtxt} "
                f"→ {'CUT' if accept else 'skip'} ({reason}): "
                f"\"{_join(words[i:best_j])[:70]}\"")
        if accept:
            spans.append((words[i]["start"], words[best_j]["start"]))
            i = best_j        # resume at the kept take (it may itself be redone again)
        else:
            i += 1
    return spans
