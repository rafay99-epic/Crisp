"""Tests for the UI waveform summary math (no ffmpeg needed)."""

import unittest

from crisp.waveform import _peaks_from_samples, _removed_flags


class PeaksTests(unittest.TestCase):
    def test_buckets_take_normalized_peak(self):
        # Two buckets: first peaks at 16384 (0.5), second at -32768 (1.0).
        peaks = _peaks_from_samples([0, 16384, 0, -32768], 2)
        self.assertEqual(peaks, [0.5, 1.0])

    def test_silence_is_zero(self):
        self.assertEqual(_peaks_from_samples([0, 0, 0, 0], 2), [0.0, 0.0])

    def test_empty_or_no_buckets(self):
        self.assertEqual(_peaks_from_samples([], 8), [])
        self.assertEqual(_peaks_from_samples([1, 2, 3], 0), [])

    def test_bucket_count_matches_request(self):
        self.assertEqual(len(_peaks_from_samples(list(range(1000)), 60)), 60)


class RemovedFlagsTests(unittest.TestCase):
    def test_center_outside_kept_is_removed(self):
        # duration 4s, keep the middle [1,3]; bucket centers 0.5/1.5/2.5/3.5.
        flags = _removed_flags(4, 4.0, [(1.0, 3.0)])
        self.assertEqual(flags, [True, False, False, True])

    def test_all_kept(self):
        self.assertEqual(_removed_flags(3, 3.0, [(0.0, 3.0)]), [False, False, False])

    def test_degenerate_inputs(self):
        self.assertEqual(_removed_flags(0, 4.0, [(0, 4)]), [])
        self.assertEqual(_removed_flags(4, 0, [(0, 4)]), [])


if __name__ == "__main__":
    unittest.main()
