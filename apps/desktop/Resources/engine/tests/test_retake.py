"""`detect_retakes` — find a flubbed take the speaker immediately repeated.

Pure transcript matching (no audio/model), so these assert the three patterns we
cut (full restart, false start, single-word stutter) and the cases we must leave
alone (rhetorical repeats far apart, ordinary recurring words)."""

import threading
import unittest

from crisp.retake import _decide, detect_retakes


def w(text, start, end):
    return {"text": text, "start": start, "end": end}


def const_judge(value):
    """A fake semantic judge returning a fixed similarity, for deterministic tests."""
    return lambda _flubbed, _corrected: value


def seq(words, *, dur=0.3, gap=0.05, breaks=None):
    """Lay `words` (list of text) end to end at `dur` each with `gap` between, except
    after an index in `breaks`, where a 0.4s pause separates the two takes."""
    breaks = breaks or {}
    out, t = [], 0.0
    for i, text in enumerate(words):
        out.append(w(text, t, t + dur))
        t += dur + (0.4 if i in breaks else gap)
    return out


class FullRestartTests(unittest.TestCase):
    def test_phrase_said_twice_cuts_the_first_take(self):
        # "the API is slow — the API is fast": the run "the API is" repeats, so the
        # first take (up to the corrected take's onset) is removed.
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"], breaks={3})
        spans = detect_retakes(words, min_run=3)
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])
        self.assertAlmostEqual(spans[0][1], words[4]["start"])  # corrected take's onset

    def test_three_takes_keep_only_the_last(self):
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "bad",
                     "the", "API", "is", "fast"], breaks={3, 7})
        spans = detect_retakes(words, min_run=3)
        self.assertEqual(len(spans), 2)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])  # first take's onset
        self.assertAlmostEqual(spans[0][1], words[4]["start"])
        self.assertAlmostEqual(spans[1][0], words[4]["start"])
        self.assertAlmostEqual(spans[1][1], words[8]["start"])


class FalseStartTests(unittest.TestCase):
    def test_abandoned_prefix_is_cut(self):
        # "so today we're— so today we're going to build"
        words = seq(["so", "today", "we're", "so", "today", "we're", "going", "to", "build"],
                    breaks={2})
        spans = detect_retakes(words, min_run=3)
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])
        self.assertAlmostEqual(spans[0][1], words[3]["start"])


class SensitivityTests(unittest.TestCase):
    def test_bare_defaults_mirror_the_default_preset(self):
        # A direct detect_retakes() call must behave like the app's default preset, not
        # a hybrid of aggressive's run floor and gentle's pause policy.
        from crisp.config import (DEFAULT_RETAKE_SENSITIVITY, RETAKE_MIN_RUN,
                                  RETAKE_MIN_RUN_NO_PAUSE, RETAKE_REQUIRE_PAUSE,
                                  RETAKE_SEM_MIN, RETAKE_SENSITIVITY)
        p = RETAKE_SENSITIVITY[DEFAULT_RETAKE_SENSITIVITY]
        self.assertEqual(RETAKE_MIN_RUN, p["min_run"])
        self.assertEqual(RETAKE_REQUIRE_PAUSE, p["require_pause"])
        self.assertEqual(RETAKE_MIN_RUN_NO_PAUSE, p["min_run_no_pause"])
        self.assertEqual(RETAKE_SEM_MIN, p["sem_min"])

    def test_default_is_aggressive_three_word_run(self):
        # The default sensitivity is now aggressive → min_run 3: a 3-word repeat cuts…
        three = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"], breaks={3})
        self.assertEqual(len(detect_retakes(three)), 1)
        # …while explicitly choosing balanced (min_run 4) leaves a 3-word repeat alone.
        self.assertEqual(detect_retakes(three, min_run=4), [])


class FuzzyMatchTests(unittest.TestCase):
    """Two takes of the same line rarely transcribe identically — fuzzy token
    matching aligns whisper's spelling variance while leaving different words apart."""

    def test_transcription_variant_phrase_is_matched(self):
        # whisper wrote the two takes slightly differently ("we're" vs "were"), but
        # it's the same redo — exact matching would miss it; fuzzy catches it.
        words = seq(["so", "today", "we're", "going", "slow",
                     "so", "today", "were", "going", "fast"], breaks={4})
        spans = detect_retakes(words, min_run=4)
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])
        self.assertAlmostEqual(spans[0][1], words[5]["start"])  # corrected take's onset

    def test_word_form_variant_is_matched(self):
        # "open"/"opens" — same word, different form. Both clear the length floor.
        words = seq(["we", "will", "open", "source", "this",
                     "we", "will", "opens", "source", "that"], breaks={4})
        self.assertEqual(len(detect_retakes(words, min_run=4)), 1)

    def test_parallel_structure_is_not_merged_by_fuzzy(self):
        # "at the startup level / at the enterprise level" — a deliberate list, not a
        # redo. The differing content word is too dissimilar to fuzzy-match, so the
        # run stays short (2) and nothing is cut.
        words = seq(["at", "the", "startup", "level",
                     "at", "the", "enterprise", "level"], breaks={3})
        self.assertEqual(detect_retakes(words, min_run=4), [])

    def test_short_words_require_exact_match(self):
        # "they"/"the" are close under a string ratio but different words; the short-
        # token guard keeps fuzzy from forging a run across them.
        words = seq(["when", "they", "run", "fast",
                     "when", "the", "run", "fast"], breaks={3})
        self.assertEqual(detect_retakes(words, min_run=4), [])


class StutterTests(unittest.TestCase):
    def test_single_word_stutter_keeps_the_last_when_enabled(self):
        # Opt-in only (stutter is off by default — see test below).
        words = seq(["the", "the", "the", "parser"])
        spans = detect_retakes(words, stutter=True)
        self.assertEqual(len(spans), 2)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])  # first "the" onset
        self.assertAlmostEqual(spans[0][1], words[1]["start"])
        self.assertAlmostEqual(spans[1][0], words[1]["start"])  # second "the" onset
        self.assertAlmostEqual(spans[1][1], words[2]["start"])  # third "the" survives

    def test_stutter_off_by_default(self):
        # A back-to-back word repeat is ambiguous (stumble vs. emphasis), so the
        # default leaves single-word repeats alone — only ≥2-word phrases are cut.
        words = seq(["the", "the", "the", "parser"])
        self.assertEqual(detect_retakes(words), [])


class MustNotCutTests(unittest.TestCase):
    def test_rhetorical_repeat_far_apart_is_kept(self):
        # Same phrase 10s later is emphasis, not a retake — the gap exceeds max_gap.
        words = (seq(["we", "will", "fight"])
                 + [w("we", 10.0, 10.3), w("will", 10.3, 10.6), w("fight", 10.6, 10.9)])
        self.assertEqual(detect_retakes(words), [])

    def test_ordinary_recurring_word_is_kept(self):
        # "the cat the dog" — one matching word, not adjacent: below min_run, no cut.
        words = seq(["the", "cat", "the", "dog"])
        self.assertEqual(detect_retakes(words), [])

    def test_intentional_emphasis_repeat_is_kept_by_default(self):
        # "that is very very important" — emphasis, not a stumble. With stutter off by
        # default the adjacent "very very" is preserved.
        words = seq(["that", "is", "very", "very", "important"])
        self.assertEqual(detect_retakes(words), [])

    def test_no_repeats_returns_nothing(self):
        words = seq(["hello", "world", "this", "is", "fine"])
        self.assertEqual(detect_retakes(words), [])

    def test_spans_are_ordered_and_non_overlapping(self):
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "bad",
                     "the", "API", "is", "fast"], breaks={3, 7})
        spans = detect_retakes(words, min_run=3)
        for a, b in spans:
            self.assertLess(a, b)
        for (_, e), (s, _) in zip(spans, spans[1:]):
            self.assertLessEqual(e, s)


class PauseAnchorTests(unittest.TestCase):
    """With silence data, the corrected take must begin right after a pause — the
    strongest filter against natural mid-sentence repetition."""

    def _words(self):
        # "the API is slow / the API is fast" laid out continuously (no built-in gap).
        return seq(["the", "API", "is", "slow", "the", "API", "is", "fast"])

    def test_repeat_without_a_pause_is_rejected(self):
        words = self._words()
        # silences=[] → there is no pause anywhere, so the repeat is not a retake.
        self.assertEqual(detect_retakes(words, min_run=3, silences=[]), [])

    def test_repeat_right_after_a_pause_is_cut(self):
        words = self._words()
        onset = words[4]["start"]                      # the corrected take's first word
        silences = [(words[3]["start"], onset)]        # a pause ending at that onset
        spans = detect_retakes(words, min_run=3, silences=silences)
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][1], onset)

    def test_pause_far_from_onset_does_not_anchor(self):
        words = self._words()
        # A silence that ends nowhere near the corrected take's onset doesn't count.
        spans = detect_retakes(words, min_run=3, silences=[(0.0, 0.2)])
        self.assertEqual(spans, [])

    def test_silences_omitted_skips_anchoring(self):
        # A bare call without silence data falls back to run-length only (the pipeline
        # always supplies silences; library users may not).
        words = self._words()
        self.assertEqual(len(detect_retakes(words, min_run=3)), 1)


class PauselessRestartTests(unittest.TestCase):
    """Aggressive catches natural mid-sentence restarts (no pause) via run length, with
    or without the semantic judge; gentle/balanced still require a pause for short ones."""

    def _restart(self):
        # "I was using this notepad to / I was using this notepad to work" with an aside
        # ("you can see") between — a real restart, NO pause. The verbatim run is 6 words.
        return seq(["I", "was", "using", "this", "notepad", "to",
                    "you", "can", "see",
                    "I", "was", "using", "this", "notepad", "to", "work"])

    def test_long_pauseless_restart_is_cut_in_aggressive(self):
        words = self._restart()
        spans = detect_retakes(words, min_run=3, require_pause=False,
                               min_run_no_pause=5, silences=[])   # no judge needed
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][0], words[0]["start"])
        self.assertAlmostEqual(spans[0][1], words[9]["start"])     # the corrected take's onset

    def test_pauseless_restart_is_kept_when_pause_is_required(self):
        # Balanced default for a 6-word repeat would still need a pause (its
        # min_run_no_pause is 7); with no pause-less path it's left alone.
        words = self._restart()
        self.assertEqual(
            detect_retakes(words, min_run=3, require_pause=True,
                           min_run_no_pause=None, silences=[]), [])

    def test_pause_required_preset_stays_pause_required_with_a_judge(self):
        # Regression: a pause-required preset (min_run_no_pause=None, like gentle) must
        # NOT start cutting pause-less restarts just because a judge is available — the
        # judge only adds precision, it never relaxes the pause requirement.
        words = self._restart()
        self.assertEqual(
            detect_retakes(words, min_run=3, require_pause=True, min_run_no_pause=None,
                           sem_min=0.5, silences=[], judge=const_judge(0.99)), [])

    def test_short_pauseless_repeat_is_not_cut_even_in_aggressive(self):
        # A 3-word pause-less repeat is below the no-pause run bar — exactly the natural
        # short repetition we must not cut.
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"])
        self.assertEqual(
            detect_retakes(words, min_run=3, require_pause=False,
                           min_run_no_pause=5, silences=[]), [])

    def test_strong_semantic_rescues_a_short_pauseless_repeat(self):
        # The optional rescue path: a high judge score admits a sub-threshold pause-less
        # repeat (logged + conservative — sem_min is set high in real config).
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"])
        spans = detect_retakes(words, min_run=3, require_pause=False, min_run_no_pause=9,
                               sem_min=0.7, silences=[], judge=const_judge(0.95))
        self.assertEqual(len(spans), 1)

    def test_noisy_judge_never_vetoes_a_pause_anchored_cut(self):
        # The embedding is too noisy to veto: a pause-anchored repeat is cut regardless
        # of a low semantic score (a real redo can legitimately score low).
        words = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"])
        silences = [(words[3]["start"], words[4]["start"])]   # pause at the redo onset
        spans = detect_retakes(words, min_run=3, require_pause=True,
                               silences=silences, judge=const_judge(0.05))
        self.assertEqual(len(spans), 1)


class DecideTests(unittest.TestCase):
    """The accept/skip matrix in isolation.
    _decide(anchored, has_pause, run, min_run_no_pause, require_pause, sim, sem_min)."""

    def test_a_pause_always_accepts(self):
        self.assertTrue(_decide(True, True, 3, None, True, None, 0.7)[0])
        self.assertTrue(_decide(True, True, 3, None, True, 0.01, 0.7)[0])   # no veto

    def test_no_silence_data_accepts(self):
        self.assertTrue(_decide(False, False, 3, None, True, None, 0.7)[0])

    def test_no_pause_requires_a_long_run(self):
        self.assertFalse(_decide(True, False, 4, 5, False, None, 0.7)[0])   # run<bar
        self.assertTrue(_decide(True, False, 6, 5, False, None, 0.7)[0])    # run>=bar

    def test_no_pause_with_no_run_bar_is_rejected(self):
        self.assertFalse(_decide(True, False, 9, None, True, None, 0.7)[0])

    def test_strong_semantic_rescues_a_short_no_pause_run(self):
        self.assertTrue(_decide(True, False, 3, 9, False, 0.9, 0.7)[0])     # sim>=bar
        self.assertFalse(_decide(True, False, 3, 9, False, 0.5, 0.7)[0])    # sim<bar


class ConcurrencyTests(unittest.TestCase):
    """Each clean runs in its own process, but detection must ALSO be safe to call
    concurrently — no shared mutable state — so several parallel cleans can never
    corrupt each other's results."""

    def test_detect_retakes_is_reentrant_across_threads(self):
        words = seq(["I", "was", "using", "this", "notepad", "to",
                     "you", "can", "see",
                     "I", "was", "using", "this", "notepad", "to", "work"])
        kwargs = dict(min_run=3, require_pause=False, min_run_no_pause=5,
                      sem_min=0.7, silences=[], judge=const_judge(0.5))
        expected = detect_retakes(words, **kwargs)
        self.assertEqual(len(expected), 1)            # sanity: it does cut

        results, errors, lock = [], [], threading.Lock()

        def worker():
            try:
                r = detect_retakes(words, **kwargs)
            except Exception as e:                    # noqa: BLE001 — record, don't swallow
                with lock:
                    errors.append(e)
                return
            with lock:
                results.append(r)

        threads = [threading.Thread(target=worker) for _ in range(16)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(errors, [])                  # no thread blew up
        self.assertEqual(len(results), 16)
        for r in results:
            self.assertEqual(r, expected)             # identical, deterministic


if __name__ == "__main__":
    unittest.main()
