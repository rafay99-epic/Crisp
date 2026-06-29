"""Platform-specific encoder selection — macOS VideoToolbox vs Windows NVENC/QSV/AMF,
with software fallback. Verifies the port stays correct on every OS from one machine."""

import unittest
from unittest import mock

from crisp.encode import hardware_quality_args, pick_hardware_encoder, video_args


class PickHardwareEncoderTests(unittest.TestCase):
    def test_macos_picks_videotoolbox(self):
        avail = {"hevc_videotoolbox", "h264_videotoolbox"}
        self.assertEqual(pick_hardware_encoder("hevc", "darwin", avail), "hevc_videotoolbox")
        self.assertEqual(pick_hardware_encoder("h264", "darwin", avail), "h264_videotoolbox")

    def test_windows_prefers_nvenc_then_qsv_then_amf(self):
        full = {"hevc_nvenc", "hevc_qsv", "hevc_amf"}
        self.assertEqual(pick_hardware_encoder("hevc", "win32", full), "hevc_nvenc")
        # NVENC absent → next preference.
        self.assertEqual(pick_hardware_encoder("hevc", "win32", {"hevc_qsv", "hevc_amf"}), "hevc_qsv")
        self.assertEqual(pick_hardware_encoder("hevc", "win32", {"hevc_amf"}), "hevc_amf")

    def test_none_when_nothing_available(self):
        # Windows ffmpeg with no HW encoders listed, or an unknown platform → software.
        self.assertIsNone(pick_hardware_encoder("hevc", "win32", set()))
        self.assertIsNone(pick_hardware_encoder("hevc", "linux", {"hevc_nvenc"}))


class HardwareQualityArgsTests(unittest.TestCase):
    def test_videotoolbox_uses_qv(self):
        self.assertEqual(hardware_quality_args("hevc_videotoolbox", "hevc", "high"), ["-q:v", "65"])

    def test_nvenc_uses_cq(self):
        # CRF-like target reused from the software CRF for the codec (hevc/high = 23).
        self.assertEqual(hardware_quality_args("hevc_nvenc", "hevc", "high"), ["-rc", "vbr", "-cq", "23"])

    def test_qsv_and_amf(self):
        self.assertEqual(hardware_quality_args("h264_qsv", "h264", "high"), ["-global_quality", "20"])
        self.assertEqual(hardware_quality_args("h264_amf", "h264", "high"),
                         ["-rc", "cqp", "-qp_i", "20", "-qp_p", "20"])


class VideoArgsPlatformTests(unittest.TestCase):
    def _args(self, platform, available):
        with mock.patch("crisp.encode.sys.platform", platform), \
             mock.patch("crisp.tools.available_hw_encoders", return_value=available):
            return video_args("hevc", hardware=True, quality="high")

    def test_macos_hardware_is_videotoolbox(self):
        self.assertIn("hevc_videotoolbox", self._args("darwin", {"hevc_videotoolbox"}))

    def test_windows_hardware_is_nvenc(self):
        args = self._args("win32", {"hevc_nvenc"})
        self.assertIn("hevc_nvenc", args)
        self.assertIn("-cq", args)
        self.assertNotIn("hevc_videotoolbox", args)  # the old hardcoded value must be gone

    def test_falls_back_to_software_when_no_hw(self):
        # Hardware requested but the platform exposes none → libx265, not a broken encoder.
        args = self._args("win32", set())
        self.assertIn("libx265", args)
        self.assertNotIn("hevc_videotoolbox", args)


class GroupCancelGuardTests(unittest.TestCase):
    def test_noop_on_windows(self):
        import clean_video
        # create=True: os.setpgrp doesn't exist on Windows, so the patch must be able to
        # create the attribute to assert it's never called.
        with mock.patch.object(clean_video.sys, "platform", "win32"), \
             mock.patch.object(clean_video.os, "setpgrp", create=True, side_effect=AssertionError("called on win32")):
            clean_video._enable_group_cancel()  # must return without touching POSIX process groups


if __name__ == "__main__":
    unittest.main()
