"""Platform-specific encoder selection — macOS VideoToolbox vs Windows NVENC/QSV/AMF,
with software fallback. Verifies the port stays correct on every OS from one machine."""

import unittest
from unittest import mock

from crisp.encode import (encoder_vendor, hardware_quality_args, pick_hardware_encoder,
                          probe_hardware, video_args)
from crisp.tools import gpu_vendors


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

    def test_vendor_filter_skips_absent_gpus(self):
        # The critical Windows fix: an AMD-only box must NOT pick NVENC just because
        # the ffmpeg build lists it (that failed at render → silent CPU encode).
        full = {"hevc_nvenc", "hevc_qsv", "hevc_amf"}
        self.assertEqual(pick_hardware_encoder("hevc", "win32", full, vendors={"amd"}), "hevc_amf")
        self.assertEqual(pick_hardware_encoder("hevc", "win32", full, vendors={"intel"}), "hevc_qsv")
        # Multi-GPU keeps the NVIDIA-first preference.
        self.assertEqual(pick_hardware_encoder("hevc", "win32", full, vendors={"amd", "nvidia"}),
                         "hevc_nvenc")
        # No recognized GPU vendor at all → nothing to run hardware on.
        self.assertIsNone(pick_hardware_encoder("hevc", "win32", full, vendors=set()))

    def test_unknown_vendors_skip_nothing(self):
        # vendors=None means "couldn't determine" — every candidate stays eligible.
        full = {"hevc_nvenc", "hevc_amf"}
        self.assertEqual(pick_hardware_encoder("hevc", "win32", full, vendors=None), "hevc_nvenc")

    def test_works_predicate_rejects_broken_encoders(self):
        # The functional check: NVENC listed but its test encode fails (no NVIDIA
        # driver) → the next candidate that actually works wins.
        full = {"hevc_nvenc", "hevc_qsv", "hevc_amf"}
        self.assertEqual(
            pick_hardware_encoder("hevc", "win32", full, works=lambda n: n == "hevc_amf"),
            "hevc_amf")
        # Nothing passes the test encode → software (the Radeon 520 case: AMF present
        # in the build and an AMD GPU present, but its VCE generation is unsupported).
        self.assertIsNone(pick_hardware_encoder("hevc", "win32", full, works=lambda n: False))


class GpuDetectionTests(unittest.TestCase):
    def test_vendor_classification(self):
        self.assertEqual(gpu_vendors(["Radeon (TM) 520"]), {"amd"})
        self.assertEqual(gpu_vendors(["NVIDIA GeForce RTX 4070"]), {"nvidia"})
        self.assertEqual(gpu_vendors(["Intel(R) UHD Graphics 770", "NVIDIA GeForce GTX 1650"]),
                         {"intel", "nvidia"})

    def test_unrecognized_is_none_not_empty(self):
        # None = "unknown" (must not filter); an empty set would wrongly skip every encoder.
        self.assertIsNone(gpu_vendors([]))
        self.assertIsNone(gpu_vendors(["Some Virtual Display Adapter"]))

    def test_encoder_vendor_mapping(self):
        self.assertEqual(encoder_vendor("h264_nvenc"), "nvidia")
        self.assertEqual(encoder_vendor("hevc_qsv"), "intel")
        self.assertEqual(encoder_vendor("h264_amf"), "amd")
        self.assertEqual(encoder_vendor("hevc_videotoolbox"), "apple")
        self.assertEqual(encoder_vendor("libx264"), "")


class ProbeHardwareTests(unittest.TestCase):
    def test_windows_reports_verified_encoders(self):
        with mock.patch("crisp.encode.sys.platform", "win32"), \
             mock.patch("crisp.tools.detect_gpu_names", return_value=["Radeon (TM) 520"]), \
             mock.patch("crisp.tools.available_hw_encoders",
                        return_value={"h264_nvenc", "hevc_nvenc", "h264_amf", "hevc_amf"}), \
             mock.patch("crisp.tools.hw_encoder_works", side_effect=lambda n: n == "h264_amf"):
            info = probe_hardware()
        self.assertEqual(info["gpus"], ["Radeon (TM) 520"])
        # AMD box: NVENC filtered by vendor; hevc_amf failed its test encode → software.
        self.assertEqual(info["encoders"], {"h264": "h264_amf", "hevc": None})

    def test_macos_is_always_videotoolbox(self):
        with mock.patch("crisp.encode.sys.platform", "darwin"), \
             mock.patch("crisp.tools.detect_gpu_names", return_value=[]):
            info = probe_hardware()
        self.assertEqual(info["encoders"],
                         {"h264": "h264_videotoolbox", "hevc": "hevc_videotoolbox"})


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
    def _args(self, platform, available, vendors=None, works=True):
        # detect_gpu_vendors/hw_encoder_works hit the registry + spawn ffmpeg — mock
        # both so these tests never depend on the machine they run on.
        with mock.patch("crisp.encode.sys.platform", platform), \
             mock.patch("crisp.tools.available_hw_encoders", return_value=available), \
             mock.patch("crisp.tools.detect_gpu_vendors", return_value=vendors), \
             mock.patch("crisp.tools.hw_encoder_works", side_effect=lambda n: works):
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

    def test_falls_back_to_software_when_test_encode_fails(self):
        # Encoders listed but none survives the functional probe (the Radeon 520
        # case) → software up front, not a doomed hardware attempt.
        args = self._args("win32", {"hevc_nvenc", "hevc_amf"}, works=False)
        self.assertIn("libx265", args)

    def test_amd_box_uses_amf_not_nvenc(self):
        args = self._args("win32", {"hevc_nvenc", "hevc_qsv", "hevc_amf"}, vendors={"amd"})
        self.assertIn("hevc_amf", args)
        self.assertNotIn("hevc_nvenc", args)


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
