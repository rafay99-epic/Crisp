"""Hardware encoder selection: Apple VideoToolbox, with software fallback.

Crisp is Apple-Silicon only, so the hardware encoder is a constant rather than a
probe — these pin that constant and the quality flags it carries, so a codec or
quality-level change can't silently swap the encoder or the scale it uses.
"""

import unittest

from crisp.encode import (HARDWARE_QV, HW_ENCODERS, hardware_quality_args,
                          probe_hardware, video_args)


class HardwareEncoderTests(unittest.TestCase):
    def test_videotoolbox_per_codec(self):
        self.assertEqual(HW_ENCODERS["h264"], "h264_videotoolbox")
        self.assertEqual(HW_ENCODERS["hevc"], "hevc_videotoolbox")

    def test_probe_reports_both_codecs(self):
        self.assertEqual(probe_hardware(), {"encoders": {"h264": "h264_videotoolbox",
                                                         "hevc": "hevc_videotoolbox"}})

    def test_probe_result_is_a_copy(self):
        # The caller serializes this straight to JSON; mutating it must not corrupt
        # the module-level table for the rest of the process.
        probe_hardware()["encoders"]["hevc"] = "tampered"
        self.assertEqual(HW_ENCODERS["hevc"], "hevc_videotoolbox")


class HardwareQualityArgsTests(unittest.TestCase):
    def test_videotoolbox_uses_qv(self):
        self.assertEqual(hardware_quality_args("high"), ["-q:v", "65"])
        self.assertEqual(hardware_quality_args("maximum"), ["-q:v", "80"])

    def test_every_quality_level_maps(self):
        for level in ("maximum", "high", "balanced", "smaller"):
            self.assertEqual(hardware_quality_args(level), ["-q:v", str(HARDWARE_QV[level])])

    def test_qv_scale_is_higher_is_better(self):
        # VideoToolbox inverts the CRF convention; a regression here would quietly
        # ship the worst quality as "maximum".
        self.assertGreater(HARDWARE_QV["maximum"], HARDWARE_QV["high"])
        self.assertGreater(HARDWARE_QV["high"], HARDWARE_QV["balanced"])
        self.assertGreater(HARDWARE_QV["balanced"], HARDWARE_QV["smaller"])


class VideoArgsTests(unittest.TestCase):
    def test_hardware_hevc_is_videotoolbox(self):
        args = video_args("hevc", hardware=True, quality="high")
        self.assertIn("hevc_videotoolbox", args)
        self.assertIn("-q:v", args)
        # QuickTime needs the hvc1 tag to play HEVC in an mp4.
        self.assertIn("hvc1", args)

    def test_hardware_h264_is_videotoolbox(self):
        self.assertIn("h264_videotoolbox", video_args("h264", hardware=True, quality="high"))

    def test_software_uses_crf(self):
        args = video_args("hevc", hardware=False, quality="high")
        self.assertIn("libx265", args)
        self.assertIn("-crf", args)
        self.assertNotIn("hevc_videotoolbox", args)


if __name__ == "__main__":
    unittest.main()
