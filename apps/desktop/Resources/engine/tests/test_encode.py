"""Encoder/container argument building — what gets handed to ffmpeg."""

import unittest

from crisp.encode import (
    HARDWARE_QV, SOFTWARE_CRF, audio_args, container_args, resolve_codecs,
    resolve_container, video_args,
)


class VideoArgsTests(unittest.TestCase):
    def test_software_h264_uses_libx264_and_crf(self):
        args = video_args("h264", hardware=False, quality="high")
        self.assertIn("libx264", args)
        self.assertIn("-crf", args)
        self.assertIn(str(SOFTWARE_CRF["h264"]["high"]), args)
        self.assertNotIn("hvc1", args)  # the hvc1 tag is HEVC-only

    def test_software_hevc_uses_libx265_and_tags_hvc1(self):
        args = video_args("hevc", hardware=False, quality="maximum")
        self.assertIn("libx265", args)
        self.assertIn(str(SOFTWARE_CRF["hevc"]["maximum"]), args)
        self.assertIn("-tag:v", args)
        self.assertIn("hvc1", args)

    def test_hardware_uses_videotoolbox_and_qv(self):
        args = video_args("hevc", hardware=True, quality="high")
        self.assertIn("hevc_videotoolbox", args)
        self.assertIn("-q:v", args)
        self.assertIn(str(HARDWARE_QV["high"]), args)
        self.assertNotIn("-crf", args)  # hardware is constant-quality, not CRF

    def test_always_forces_yuv420p(self):
        for hw in (True, False):
            self.assertIn("yuv420p", video_args("h264", hardware=hw, quality="high"))

    def test_vp9_uses_libvpx_in_constant_quality_software(self):
        # VP9 is software-only (no VideoToolbox encoder) and needs -b:v 0 to make
        # -crf a quality target rather than a bitrate cap — even if hardware is asked.
        args = video_args("vp9", hardware=True, quality="high")
        self.assertIn("libvpx-vp9", args)
        self.assertIn("-crf", args)
        self.assertIn(str(SOFTWARE_CRF["vp9"]["high"]), args)
        self.assertEqual(args[args.index("-b:v") + 1], "0")
        self.assertNotIn("videotoolbox", " ".join(args))

    def test_unknown_codec_and_quality_fall_back(self):
        # A bad codec falls back to h264, a bad quality to "high" — never a crash.
        args = video_args("xyz", hardware=False, quality="ludicrous")
        self.assertIn("libx264", args)
        self.assertIn(str(SOFTWARE_CRF["h264"]["high"]), args)


class AudioArgsTests(unittest.TestCase):
    def test_aac_and_opus_encoders(self):
        self.assertIn("aac", audio_args("aac", 192))
        self.assertIn("libopus", audio_args("opus", 128))

    def test_bitrate_formatting(self):
        self.assertIn("192k", audio_args("aac", 192))
        self.assertIn("256k", audio_args("opus", 256))


class ResolveContainerTests(unittest.TestCase):
    def test_explicit_choice_wins(self):
        self.assertEqual(resolve_container("mkv", ".mp4"), "mkv")
        self.assertEqual(resolve_container("mov", ".mkv"), "mov")

    def test_explicit_unknown_falls_back_to_mp4(self):
        self.assertEqual(resolve_container("flv", ".mkv"), "mp4")

    def test_auto_matches_input_extension(self):
        self.assertEqual(resolve_container("auto", ".mkv"), "mkv")
        self.assertEqual(resolve_container("auto", ".mp4"), "mp4")
        self.assertEqual(resolve_container("auto", ".MOV"), "mov")  # case-insensitive

    def test_auto_keeps_webm_input(self):
        # WebM is a supported container now, so an .webm source stays .webm.
        self.assertEqual(resolve_container("auto", ".webm"), "webm")
        self.assertEqual(resolve_container("webm", ".mp4"), "webm")

    def test_auto_on_unmuxable_input_falls_back_to_mp4(self):
        # An .avi / .flv source has no matching output container we keep, so "auto"
        # lands on mp4 rather than producing something we can't write.
        self.assertEqual(resolve_container("auto", ".avi"), "mp4")
        self.assertEqual(resolve_container("auto", ".flv"), "mp4")


class ResolveCodecsTests(unittest.TestCase):
    def test_webm_forces_vp9_opus_software_with_notes(self):
        v, a, hw, notes = resolve_codecs("webm", "hevc", "aac", hardware=True)
        self.assertEqual((v, a, hw), ("vp9", "opus", False))
        self.assertEqual(len(notes), 3)  # one per coercion, so nothing is silent

    def test_webm_with_compatible_choices_changes_nothing(self):
        v, a, hw, notes = resolve_codecs("webm", "vp9", "opus", hardware=False)
        self.assertEqual((v, a, hw), ("vp9", "opus", False))
        self.assertEqual(notes, [])

    def test_non_webm_leaves_normal_codecs_alone(self):
        v, a, hw, notes = resolve_codecs("mp4", "hevc", "aac", hardware=True)
        self.assertEqual((v, a, hw), ("hevc", "aac", True))
        self.assertEqual(notes, [])

    def test_vp9_outside_webm_is_coerced_to_h264(self):
        # A non-webm container can't hold VP9, so it's coerced back (with a note).
        v, a, hw, notes = resolve_codecs("mp4", "vp9", "aac", hardware=False)
        self.assertEqual(v, "h264")
        self.assertTrue(notes)


class ContainerArgsTests(unittest.TestCase):
    def test_faststart_only_for_mp4_family(self):
        for c in ("mp4", "mov", "m4v"):
            self.assertEqual(container_args(c), ["-movflags", "+faststart"])

    def test_no_faststart_for_mkv_ts_or_webm(self):
        self.assertEqual(container_args("mkv"), [])
        self.assertEqual(container_args("ts"), [])
        self.assertEqual(container_args("webm"), [])


if __name__ == "__main__":
    unittest.main()
