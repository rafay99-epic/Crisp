"""`detect_retakes` — find a flubbed take the speaker immediately repeated.

Pure transcript matching (no audio/model), so these assert the three patterns we
cut (full restart, false start, single-word stutter) and the cases we must leave
alone (rhetorical repeats far apart, ordinary recurring words)."""

import unittest

from crisp.retake import detect_retakes


def w(text, start, end):
    return {"text": text, "start": start, "end": end}


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
    def test_balanced_default_needs_four_word_run(self):
        # The default (balanced) min_run is 4: a 3-word repeat isn't enough…
        three = seq(["the", "API", "is", "slow", "the", "API", "is", "fast"], breaks={3})
        self.assertEqual(detect_retakes(three), [])
        # …a 4-word run is.
        four = seq(["the", "API", "is", "really", "slow",
                    "the", "API", "is", "really", "fast"], breaks={4})
        self.assertEqual(len(detect_retakes(four)), 1)


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


if __name__ == "__main__":
    unittest.main()
