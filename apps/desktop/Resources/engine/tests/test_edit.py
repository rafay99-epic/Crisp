"""The cut planner — `build_keep_segments` turns detected pauses and filler
words into the list of segments to KEEP. This is the heart of the engine, and
it's pure arithmetic, so it's the most valuable thing to pin down with tests."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from crisp.edit import (
    _output_owner, build_keep_segments, load_keep_segments, tag_output_source, unique_output_path,
)
from crisp.errors import CleanError


def word(text, start, end):
    return {"text": text, "start": start, "end": end}


class OutputCollisionTests(unittest.TestCase):
    def test_free_name_used_as_is(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "talk_cleaned.mov"
            self.assertEqual(unique_output_path(out, Path("/v/talk.mov")), out)

    def test_different_source_gets_numbered_copy(self):
        # An existing cleaned file from another (untagged) source must not be
        # overwritten — a different source maps to _1.
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "talk_cleaned.mov"
            out.write_bytes(b"existing")
            got = unique_output_path(out, Path("/v/talk.mov"))
            self.assertEqual(got, Path(d) / "talk_cleaned_1.mov")

    def test_same_source_reuses_its_output(self):
        # Re-cleaning the same source overwrites its own previous output (no pile-up).
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "talk_cleaned.mov"
            out.write_bytes(b"existing")
            src = Path("/v/talk.mov")
            tag_output_source(out, src)
            if _output_owner(out) != os.fsencode(str(src)):
                self.skipTest("filesystem doesn't support extended attributes")
            self.assertEqual(unique_output_path(out, src), out)

    def test_tag_round_trips(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "talk_cleaned.mov"
            out.write_bytes(b"x")
            src = Path("/v/talk.mov")
            tag_output_source(out, src)
            owner = _output_owner(out)
            if owner is None:
                self.skipTest("filesystem doesn't support extended attributes")
            self.assertEqual(owner, os.fsencode(str(src)))


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


class LoadKeepSegmentsTests(unittest.TestCase):
    """The review-timeline keep-list loader: validate, clamp, sort, merge — and
    never silently render the whole video on a broken edit list."""

    def _write(self, obj):
        f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(obj, f)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_valid_sorts_and_clamps(self):
        path = self._write({"keep": [[5.0, 8.0], [0.0, 2.0]]})
        keep = load_keep_segments(path, duration=10.0)
        self.assertEqual(keep, [(0.0, 2.0), (5.0, 8.0)])

    def test_clamps_to_duration_and_zero(self):
        path = self._write({"keep": [[-1.0, 3.0], [8.0, 99.0]]})
        keep = load_keep_segments(path, duration=10.0)
        self.assertEqual(keep, [(0.0, 3.0), (8.0, 10.0)])

    def test_merges_overlapping(self):
        path = self._write({"keep": [[0.0, 4.0], [3.5, 6.0]]})
        keep = load_keep_segments(path, duration=10.0)
        self.assertEqual(keep, [(0.0, 6.0)])

    def test_skips_malformed_entries_but_keeps_valid(self):
        path = self._write({"keep": [["x", 2], [1.0, 3.0], [5.0]]})
        keep = load_keep_segments(path, duration=10.0)
        self.assertEqual(keep, [(1.0, 3.0)])

    def test_skips_dict_and_nonfinite_entries(self):
        # Dict-shaped entries (would KeyError) and nan/inf are skipped, not crashed on.
        path = self._write({"keep": [{"start": 0, "end": 2}, ["nan", "inf"],
                                     [float("inf"), 5.0], [1.0, 3.0]]})
        keep = load_keep_segments(path, duration=10.0)
        self.assertEqual(keep, [(1.0, 3.0)])

    def test_empty_keep_raises(self):
        path = self._write({"keep": []})
        with self.assertRaises(CleanError):
            load_keep_segments(path, duration=10.0)

    def test_all_zero_length_raises(self):
        path = self._write({"keep": [[2.0, 2.0], [5.0, 5.005]]})
        with self.assertRaises(CleanError):
            load_keep_segments(path, duration=10.0)

    def test_missing_keep_key_raises(self):
        path = self._write({"nope": 1})
        with self.assertRaises(CleanError):
            load_keep_segments(path, duration=10.0)

    def test_unreadable_file_raises(self):
        with self.assertRaises(CleanError):
            load_keep_segments("/no/such/file.json", duration=10.0)


if __name__ == "__main__":
    unittest.main()
