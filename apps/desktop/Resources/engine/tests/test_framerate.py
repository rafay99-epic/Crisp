"""Frame-rate policy: VFR detection + which constant rate to normalize to."""

import unittest

from crisp.framerate import is_vfr, parse_fraction, resolve_target_fps


class ParseFractionTests(unittest.TestCase):
    def test_fraction_and_plain(self):
        self.assertAlmostEqual(parse_fraction("30000/1001"), 29.97, places=2)
        self.assertEqual(parse_fraction("30/1"), 30.0)
        self.assertEqual(parse_fraction("60"), 60.0)

    def test_unknown_and_malformed_are_none(self):
        for bad in ("", "  ", "N/A", "0/0", "30/0", "abc", None):
            self.assertIsNone(parse_fraction(bad))


class IsVFRTests(unittest.TestCase):
    def test_cfr_average_equals_base(self):
        self.assertFalse(is_vfr(30.0, 30.0))
        # 30000/1001 reported both ways is still CFR (NTSC).
        self.assertFalse(is_vfr(29.97, 29.97))

    def test_rounding_within_tolerance_is_not_vfr(self):
        # Base 30/1 vs average 30000/1001 — a 0.1% gap, just container rounding.
        self.assertFalse(is_vfr(30.0, 29.97))

    def test_average_well_below_base_is_vfr(self):
        # A screen recording: 60 base, ~24 average → VFR.
        self.assertTrue(is_vfr(60.0, 24.0))

    def test_unknown_rates_are_not_vfr(self):
        self.assertFalse(is_vfr(None, 30.0))
        self.assertFalse(is_vfr(30.0, None))
        self.assertFalse(is_vfr(0.0, 0.0))


class ResolveTargetFPSTests(unittest.TestCase):
    def test_passthrough_never_normalizes(self):
        self.assertIsNone(resolve_target_fps("passthrough", 0, "60/1", "24/1"))

    def test_constant_always_forces_requested(self):
        self.assertEqual(resolve_target_fps("constant", 30, "60/1", "60/1"), "30")
        # A constant mode with no usable value can't force a rate.
        self.assertIsNone(resolve_target_fps("constant", 0, "60/1", "60/1"))

    def test_auto_leaves_cfr_untouched(self):
        self.assertIsNone(resolve_target_fps("auto", 0, "30/1", "30/1"))
        self.assertIsNone(resolve_target_fps("auto", 0, "30000/1001", "30000/1001"))

    def test_auto_normalizes_vfr_to_base_rate(self):
        # VFR (60 base, 24 avg) with no override → normalize to the nominal base.
        self.assertEqual(resolve_target_fps("auto", 0, "60/1", "24/1"), "60/1")

    def test_auto_override_wins_on_vfr(self):
        # A caller-supplied rate beats the detected base on a VFR source.
        self.assertEqual(resolve_target_fps("auto", 30, "60/1", "24/1"), "30")

    def test_auto_falls_back_to_average_when_base_implausible(self):
        # Some containers report a huge timebase-derived base; use the average then.
        self.assertEqual(resolve_target_fps("auto", 0, "90000/1", "30/1"), "30/1")

    def test_auto_no_change_when_rates_unreadable(self):
        self.assertIsNone(resolve_target_fps("auto", 0, "N/A", "0/0"))

    def test_constant_with_no_value_resolves_none(self):
        # The pipeline turns this None into a CleanError (constant mode must force a
        # rate); a zero/garbage request must never silently pass through.
        self.assertIsNone(resolve_target_fps("constant", 0, "60/1", "60/1"))
        self.assertIsNone(resolve_target_fps("constant", -5, "60/1", "60/1"))


if __name__ == "__main__":
    unittest.main()
