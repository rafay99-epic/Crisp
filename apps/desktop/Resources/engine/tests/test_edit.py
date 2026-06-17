"""The cut planner — `build_keep_segments` turns detected pauses and filler
words into the list of segments to KEEP. This is the heart of the engine, and
it's pure arithmetic, so it's the most valuable thing to pin down with tests."""

import unittest

from crisp.edit import build_keep_segments


def word(text, start, end):
    return {"text": text, "start": start, "end": end}


class BuildKeepSegmentsTests(unittest.TestCase):
    def test_no_pauses_or_fillers_keeps_everything(self):
        keep, stats = build_keep_segments(
            words=[word("hello", 0.0, 1.0)], silences=[], duration=10.0,
            keep_pause=0.15, min_keep=0.05)
        self.assertEqual(keep, [(0.0, 10.0)])
        self.assertEqual(stats, {"fillers": 0, "pauses": 0})

    def test_single_pause_is_trimmed_with_breathing_room(self):
        # A 3–5s silence with 0.15s breathing room removes only (3.15, 4.85),
        # leaving the padding attached to the surrounding speech.
        keep, stats = build_keep_segments(
            words=[], silences=[(3.0, 5.0)], duration=10.0,
            keep_pause=0.15, min_keep=0.05)
        self.assertEqual(len(keep), 2)
        self.assertAlmostEqual(keep[0][0], 0.0)
        self.assertAlmostEqual(keep[0][1], 3.15)
        self.assertAlmostEqual(keep[1][0], 4.85)
        self.assertAlmostEqual(keep[1][1], 10.0)
        self.assertEqual(stats["pauses"], 1)

    def test_filler_word_is_removed(self):
        keep, stats = build_keep_segments(
            words=[word("um", 1.0, 1.3)], silences=[], duration=5.0,
            keep_pause=0.1, min_keep=0.05)
        self.assertEqual(len(keep), 2)
        self.assertAlmostEqual(keep[0][1], 1.0)
        self.assertAlmostEqual(keep[1][0], 1.3)
        self.assertEqual(stats["fillers"], 1)

    def test_real_word_is_not_removed(self):
        keep, stats = build_keep_segments(
            words=[word("hello", 1.0, 1.3)], silences=[], duration=5.0,
            keep_pause=0.1, min_keep=0.05)
        self.assertEqual(keep, [(0.0, 5.0)])
        self.assertEqual(stats["fillers"], 0)

    def test_overlapping_removals_are_merged(self):
        # A pause (2–4, no padding) and a filler (3–5) overlap and must merge into
        # a single (2, 5) cut — not two, and not a doubled count of kept islands.
        keep, _ = build_keep_segments(
            words=[word("uh", 3.0, 5.0)], silences=[(2.0, 4.0)], duration=8.0,
            keep_pause=0.0, min_keep=0.05)
        self.assertEqual(keep, [(0.0, 2.0), (5.0, 8.0)])

    def test_fragment_shorter_than_min_keep_is_dropped(self):
        # The 0.02s sliver before the cut is below min_keep (0.05) and is dropped,
        # so only the tail survives.
        keep, _ = build_keep_segments(
            words=[], silences=[(0.02, 3.0)], duration=5.0,
            keep_pause=0.0, min_keep=0.05)
        self.assertEqual(keep, [(3.0, 5.0)])

    def test_removals_are_clamped_to_the_clip(self):
        # A silence running past the end mustn't produce an out-of-range keep.
        keep, _ = build_keep_segments(
            words=[], silences=[(8.0, 12.0)], duration=10.0,
            keep_pause=0.0, min_keep=0.05)
        for s, e in keep:
            self.assertGreaterEqual(s, 0.0)
            self.assertLessEqual(e, 10.0)

    def test_counts_each_kind(self):
        _, stats = build_keep_segments(
            words=[word("um", 1.0, 1.2), word("uh", 6.0, 6.2), word("real", 2.0, 2.5)],
            silences=[(3.0, 4.0)], duration=10.0, keep_pause=0.1, min_keep=0.05)
        self.assertEqual(stats["fillers"], 2)
        self.assertEqual(stats["pauses"], 1)


if __name__ == "__main__":
    unittest.main()
