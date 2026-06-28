"""Encoder/container argument building — what gets handed to ffmpeg."""

import unittest
from pathlib import Path

from crisp.encode import (
    HARDWARE_QV, SOFTWARE_CRF, TEN_BIT_PIX_FMT, audio_args, container_args, default_output_path,
    is_high_bit_depth, resolve_codecs, resolve_container, resolve_pix_fmt, video_args,
)


class OutputPathTests(unittest.TestCase):
    def test_defaults_beside_source(self):
        # No out_dir → "<name>_cleaned.<container>" right beside the input.
        out = default_output_path("/videos/talk.mov", "mov")
        self.assertEqual(out, Path("/videos/talk_cleaned.mov"))

    def test_out_dir_keeps_cleaned_name(self):
        # An out_dir (e.g. a NAS) → same name, different folder.
        out = default_output_path("/videos/talk.mov", "mov", out_dir="/Volumes/NAS/clean")
        self.assertEqual(out, Path("/Volumes/NAS/clean/talk_cleaned.mov"))

    def test_container_drives_extension(self):
        # The resolved container is the extension, independent of the source's.
        out = default_output_path("/videos/talk.mkv", "mp4", out_dir="/out")
        self.assertEqual(out, Path("/out/talk_cleaned.mp4"))


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


class HighBitDepthTests(unittest.TestCase):
    def test_8bit_420_is_not_high(self):
        for pf in ("yuv420p", "nv12", "yuvj420p", ""):
            self.assertFalse(is_high_bit_depth(pf), pf)

    def test_10_12_16bit_and_wide_chroma_are_high(self):
        for pf in ("yuv420p10le", "yuv422p10le", "yuv444p10le", "p010le",
                   "yuv420p12le", "yuv422p", "yuv444p", "yuv420p16le", "yuv420p14le",
                   "gbrp10le", "gbrp16le"):
            self.assertTrue(is_high_bit_depth(pf), pf)

    def test_packed_high_bit_depth_rgb_is_high(self):
        # Packed 16-bit / 10-bit RGB(A) must be preserved too, not crushed to 8-bit yuv420p.
        for pf in ("rgb48le", "bgr48le", "rgba64le", "bgra64be", "x2rgb10le"):
            self.assertTrue(is_high_bit_depth(pf), pf)
        for pf in ("rgb24", "rgba", "bgr24", "0rgb"):   # 8-bit RGB stays 8-bit
            self.assertFalse(is_high_bit_depth(pf), pf)

    def test_video_args_threads_pix_fmt(self):
        # The editor copy passes the source's own pixel format instead of forcing 8-bit.
        self.assertIn("yuv420p10le", video_args("hevc", False, "high", "yuv420p10le"))
        self.assertIn("yuv420p", video_args("hevc", False, "high"))   # default unchanged


class ResolvePixFmtTests(unittest.TestCase):
    """Color-depth → output pixel format (the source-aware bit-depth decision)."""

    def test_auto_preserves_high_bit_depth_source(self):
        # A 10-bit / wide-chroma source is matched exactly (incl. its chroma), with a note.
        for src in ("yuv420p10le", "yuv422p10le", "yuv444p10le", "yuv420p12le", "yuv422p"):
            pix, notes = resolve_pix_fmt("auto", src, "hevc")
            self.assertEqual(pix, src, src)
            self.assertTrue(notes, src)   # the preserve is surfaced, never silent

    def test_auto_keeps_8bit_and_unknown_at_yuv420p(self):
        # Plain 8-bit and an unreadable/empty pix_fmt both stay the safe 8-bit 4:2:0 — no note.
        for src in ("yuv420p", "nv12", "yuvj420p", ""):
            pix, notes = resolve_pix_fmt("auto", src, "hevc")
            self.assertEqual(pix, "yuv420p", src)
            self.assertEqual(notes, [], src)

    def test_force_8_always_yuv420p_and_notes_a_real_downgrade(self):
        pix, notes = resolve_pix_fmt("8", "yuv422p10le", "hevc")
        self.assertEqual(pix, "yuv420p")
        self.assertTrue(notes)                     # crushing a 10-bit source is surfaced
        pix, notes = resolve_pix_fmt("8", "yuv420p", "hevc")
        self.assertEqual(pix, "yuv420p")
        self.assertEqual(notes, [])                # 8-bit → 8-bit isn't a downgrade

    def test_force_10_upconverts_8bit_with_a_note(self):
        pix, notes = resolve_pix_fmt("10", "yuv420p", "hevc")
        self.assertEqual(pix, TEN_BIT_PIX_FMT)     # yuv420p10le
        self.assertTrue(notes)                     # "no quality gain" warning surfaced
        # An unknown/empty source still yields a real 10-bit target.
        self.assertEqual(resolve_pix_fmt("10", "", "h264")[0], TEN_BIT_PIX_FMT)

    def test_force_10_preserves_an_already_deep_source(self):
        # Already ≥10-bit: keep the source format (incl. its chroma), don't coerce to 4:2:0.
        for src in ("yuv422p10le", "yuv444p10le", "yuv420p12le"):
            self.assertEqual(resolve_pix_fmt("10", src, "hevc")[0], src, src)

    def test_target_high_bit_depth_implies_software(self):
        # The render ladder keys "needs software encoder" off is_high_bit_depth(target);
        # every depth-preserving/forcing result must classify as high so it picks software.
        for mode, src in (("auto", "yuv420p10le"), ("10", "yuv420p"), ("10", "yuv422p10le")):
            self.assertTrue(is_high_bit_depth(resolve_pix_fmt(mode, src, "hevc")[0]), (mode, src))
        # The 8-bit results must NOT (they keep the hardware fast path).
        for mode, src in (("auto", "yuv420p"), ("8", "yuv420p10le")):
            self.assertFalse(is_high_bit_depth(resolve_pix_fmt(mode, src, "hevc")[0]), (mode, src))


if __name__ == "__main__":
    unittest.main()
