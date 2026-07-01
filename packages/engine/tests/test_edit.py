"""The cut planner — `build_keep_segments` turns detected pauses and filler
words into the list of segments to KEEP. This is the heart of the engine, and
it's pure arithmetic, so it's the most valuable thing to pin down with tests."""

import array
import json
import os
import tempfile
import unittest
import wave
from pathlib import Path

from crisp.edit import (
    _nearest_zero_crossing, _output_owner, build_filter_graph, build_keep_segments,
    load_keep_segments, output_duration, snap_keep_to_zero_crossings, tag_output_source,
    unique_output_path,
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
        self.assertEqual(stats, {"fillers": 0, "pauses": 0, "retakes": 0})

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
        self.assertEqual(stats["retakes"], 0)

    def test_retake_span_is_removed_and_counted(self):
        # A retake span (the flubbed first take) is cut wholesale, like a pause.
        keep, stats = build_keep_segments(
            words=[], silences=[], duration=10.0, keep_pause=0.1, min_keep=0.05,
            retakes=[(2.0, 4.0)])
        self.assertEqual(keep, [(0.0, 2.0), (4.0, 10.0)])
        self.assertEqual(stats["retakes"], 1)


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


class BuildFilterGraphTests(unittest.TestCase):
    """The cut-smoothing filtergraph (Phase 1 fade / Phase 2 crossfade). Pure string
    building, so we can pin the exact ffmpeg graph without running ffmpeg."""

    def test_plain_cut_has_no_fades_and_concats(self):
        lines = build_filter_graph([(0.0, 2.0), (3.0, 5.0)], fade=0.0, crossfade=0.0)
        graph = "\n".join(lines)
        self.assertNotIn("afade", graph)
        self.assertNotIn("xfade", graph)
        self.assertIn("concat=n=2:v=1:a=1[outv][outa]", graph)

    def test_fade_adds_in_out_to_each_segment(self):
        lines = build_filter_graph([(0.0, 2.0), (3.0, 5.0)], fade=0.010, crossfade=0.0)
        graph = "\n".join(lines)
        self.assertEqual(graph.count("afade=t=in:st=0:d=0.010000"), 2)
        # fade-out starts fade-length before the (reset) segment end (2.0 - 0.010).
        self.assertIn("afade=t=out:st=1.990000:d=0.010000", graph)
        self.assertIn("concat=n=2:v=1:a=1[outv][outa]", graph)

    def test_fade_is_capped_at_half_a_short_segment(self):
        lines = build_filter_graph([(0.0, 0.01)], fade=0.010, crossfade=0.0)
        graph = "\n".join(lines)
        self.assertIn("afade=t=in:st=0:d=0.005000", graph)   # min(0.010, 0.01/2)

    def test_crossfade_uses_matched_xfade_and_acrossfade(self):
        lines = build_filter_graph([(0.0, 2.0), (3.0, 5.0), (6.0, 9.0)],
                                   fade=0.010, crossfade=0.1)
        graph = "\n".join(lines)
        self.assertNotIn("afade", graph)                  # crossfade overrides per-segment fade
        self.assertNotIn("concat=", graph)
        # First dissolve offset = dur0 - c = 2.0 - 0.1; last lands on [outv]/[outa].
        self.assertIn("xfade=transition=fade:duration=0.100000:offset=1.900000", graph)
        self.assertIn("xfade=transition=fade:duration=0.100000:offset=3.800000[outv]", graph)
        self.assertIn("acrossfade=d=0.100000[outa]", graph)

    def test_crossfade_is_clamped_to_half_the_shortest_segment(self):
        # A 0.05s sliver with a 0.1s crossfade would over-run the segment; the dissolve
        # is clamped to min(0.1, 0.05/2) = 0.025s so it can't break.
        lines = build_filter_graph([(0.0, 2.0), (3.0, 3.05)], fade=0.0, crossfade=0.1)
        graph = "\n".join(lines)
        self.assertIn("xfade=transition=fade:duration=0.025000", graph)
        self.assertIn("acrossfade=d=0.025000", graph)

    def test_crossfade_falls_back_to_concat_for_single_segment(self):
        lines = build_filter_graph([(0.0, 2.0)], fade=0.0, crossfade=0.1)
        graph = "\n".join(lines)
        self.assertIn("concat=n=1:v=1:a=1[outv][outa]", graph)
        self.assertNotIn("xfade", graph)

    def test_empty_keep_raises(self):
        # An empty keep list would emit concat=n=0 (invalid ffmpeg) — guard it.
        with self.assertRaises(ValueError):
            build_filter_graph([], fade=0.010, crossfade=0.0)


class OutputDurationTests(unittest.TestCase):
    def test_no_crossfade_is_raw_sum(self):
        self.assertAlmostEqual(output_duration([(0.0, 2.0), (3.0, 5.0), (6.0, 9.0)]), 7.0)

    def test_crossfade_overlaps_each_join(self):
        # c = min(0.1, min(2,2,3)/2) = 0.1; 2 joins → 7.0 - 2*0.1 = 6.8
        self.assertAlmostEqual(output_duration([(0.0, 2.0), (3.0, 5.0), (6.0, 9.0)], crossfade=0.1), 6.8)

    def test_single_segment_has_no_overlap(self):
        self.assertAlmostEqual(output_duration([(0.0, 5.0)], crossfade=0.1), 5.0)


class ZeroCrossingTests(unittest.TestCase):
    def test_finds_nearest_crossing(self):
        # Sign flips between index 4 (+) and 5 (-): the crossing is at index 5.
        samples = [100, 100, 100, 100, 100, -100, -100, -100]
        self.assertEqual(_nearest_zero_crossing(samples, center=3, max_off=5), 5)

    def test_returns_center_when_no_crossing_in_window(self):
        samples = [100, 100, 100, 100, 100, -100, -100, -100]
        self.assertEqual(_nearest_zero_crossing(samples, center=1, max_off=2), 1)

    def test_empty_is_safe(self):
        self.assertEqual(_nearest_zero_crossing([], center=3, max_off=5), 3)


class SnapKeepTests(unittest.TestCase):
    """Phase 3: snap cut boundaries onto zero-crossings, reading a real (tiny) WAV."""

    def _wav(self, samples, sr=1000):
        f = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        f.close()
        self.addCleanup(os.unlink, f.name)
        with wave.open(f.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes(array.array("h", samples).tobytes())
        return f.name

    def test_interior_boundary_snaps_to_crossing(self):
        # +100 for the first half, -100 for the second → one crossing at sample 500.
        path = self._wav([100] * 500 + [-100] * 500)
        keep = [(0.0, 0.497), (0.6, 1.0)]      # 0.497 is 3 samples shy of the crossing
        snapped = snap_keep_to_zero_crossings(keep, path, window_s=0.012)
        self.assertAlmostEqual(snapped[0][1], 0.5, places=3)   # 0.497 → 0.500
        self.assertAlmostEqual(snapped[1][0], 0.6, places=3)   # no crossing nearby → unchanged

    def test_single_segment_is_left_alone(self):
        path = self._wav([100] * 500 + [-100] * 500)
        keep = [(0.0, 1.0)]
        self.assertEqual(snap_keep_to_zero_crossings(keep, path, window_s=0.012), keep)

    def test_missing_wav_returns_keep_unchanged(self):
        keep = [(0.0, 0.5), (0.6, 1.0)]
        self.assertEqual(snap_keep_to_zero_crossings(keep, "/no/such.wav", window_s=0.012), keep)

    def test_snap_end_encroaching_a_narrow_gap_never_drops_the_next_segment(self):
        # One zero-crossing region at samples 412-414. The first segment's end (0.40)
        # snaps forward toward it and the next segment (0.41-0.425) would collapse —
        # the end-cap + original-fallback must keep the next segment whole.
        samples = [100] * 800
        for i in (412, 413, 414):
            samples[i] = -100
        path = self._wav(samples)
        keep = [(0.0, 0.40), (0.41, 0.425)]
        snapped = snap_keep_to_zero_crossings(keep, path, window_s=0.012)
        self.assertEqual(len(snapped), 2)                       # nothing dropped
        self.assertAlmostEqual(snapped[1][0], 0.41, places=3)   # kept its original span
        self.assertAlmostEqual(snapped[1][1], 0.425, places=3)
        self.assertLessEqual(snapped[0][1], snapped[1][0])      # no overlap

    def test_snap_never_drops_a_segment_it_would_shrink(self):
        # All +100 except samples 505-507 = -100 → zero-crossings at index 505 and 508.
        samples = [100] * 1000
        for i in (505, 506, 507):
            samples[i] = -100
        path = self._wav(samples)
        # The short middle segment's start (0.500) snaps to 0.505 and end (0.515) to
        # 0.508 → 3ms, below the floor. The fix must keep its ORIGINAL bounds, not drop it.
        keep = [(0.0, 0.4), (0.5, 0.515), (0.7, 1.0)]
        snapped = snap_keep_to_zero_crossings(keep, path, window_s=0.012)
        self.assertEqual(len(snapped), 3)                  # nothing dropped
        self.assertAlmostEqual(snapped[1][0], 0.5, places=3)
        self.assertAlmostEqual(snapped[1][1], 0.515, places=3)


if __name__ == "__main__":
    unittest.main()
