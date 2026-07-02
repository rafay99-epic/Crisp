"""Encoder/container argument building — what gets handed to ffmpeg."""

import unittest
from pathlib import Path
from unittest import mock

from crisp.encode import (
    HARDWARE_QV, SOFTWARE_CRF, TEN_BIT_PIX_FMT, audio_args, container_args, default_output_path,
    hdr_x265_params, is_deep_pix_fmt, is_high_bit_depth, resolve_codecs, resolve_container,
    resolve_pix_fmt, video_args,
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
        # Pin the platform: on Windows the hardware path probes the real GPU instead
        # (covered in test_encode_platform), which would make this machine-dependent.
        with mock.patch("crisp.encode.sys.platform", "darwin"):
            args = video_args("hevc", hardware=True, quality="high")
        self.assertIn("hevc_videotoolbox", args)
        self.assertIn("-q:v", args)
        self.assertIn(str(HARDWARE_QV["high"]), args)
        self.assertNotIn("-crf", args)  # hardware is constant-quality, not CRF

    def test_always_forces_yuv420p(self):
        with mock.patch("crisp.encode.sys.platform", "darwin"):  # keep hardware=True machine-independent
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

    def test_alias_wide_chroma_names_are_high(self):
        # 8-bit wide-chroma formats whose names lack the 444/422 digits must still count as
        # high (worth preserving) — otherwise auto mode silently subsamples them to 4:2:0.
        for pf in ("nv16", "nv61", "nv24", "nv42", "gbrp", "gbrap"):
            self.assertTrue(is_high_bit_depth(pf), pf)
        self.assertFalse(is_high_bit_depth("nv12"), "nv12 is 4:2:0 8-bit, not high")

    def test_video_args_threads_pix_fmt(self):
        # The editor copy passes the source's own pixel format instead of forcing 8-bit.
        self.assertIn("yuv420p10le", video_args("hevc", False, "high", "yuv420p10le"))
        self.assertIn("yuv420p", video_args("hevc", False, "high"))   # default unchanged

    def test_hdr_params_only_ride_libx265(self):
        params = "master-display=G(8500,39850)B(6550,2300)R(35400,14600)WP(15635,16450)L(10000000,1)"
        # Software HEVC (libx265) on a DEEP pixel format is the only place HDR10 metadata rides.
        sw_hevc = video_args("hevc", False, "high", "yuv420p10le", hdr_params=params)
        self.assertIn("-x265-params", sw_hevc)
        self.assertEqual(sw_hevc[sw_hevc.index("-x265-params") + 1], params)
        # Hardware HEVC (VideoToolbox), H.264, and VP9 must NOT receive -x265-params.
        # (Platform pinned: the Windows hardware path probes the real GPU and would
        # fall back to libx265 — which then rightly carries the params.)
        with mock.patch("crisp.encode.sys.platform", "darwin"):
            self.assertNotIn("-x265-params", video_args("hevc", True, "high", "yuv420p10le", hdr_params=params))
        self.assertNotIn("-x265-params", video_args("h264", False, "high", "yuv420p10le", hdr_params=params))
        self.assertNotIn("-x265-params", video_args("vp9", False, "high", "yuv420p10le", hdr_params=params))
        # No metadata → no flag, even on libx265.
        self.assertNotIn("-x265-params", video_args("hevc", False, "high", "yuv420p10le"))

    def test_hdr_params_only_explicitly_written_on_deep_output(self):
        # We only add the explicit HDR10 -x265-params on a deep (≥10-bit) output; an 8-bit
        # fallback gets no explicit params (ffmpeg auto-propagates the source's own metadata,
        # which is correct for the still-PQ pixels — we don't strip, since we don't tone-map).
        params = "max-cll=1000,400"
        for pix in ("yuv420p", "yuv422p", "yuv444p"):   # all 8-bit → no explicit HDR params
            self.assertNotIn("-x265-params",
                             video_args("hevc", False, "high", pix, hdr_params=params), pix)
        for pix in ("yuv420p10le", "yuv420p12le"):      # deep → explicit params written
            self.assertIn("-x265-params",
                          video_args("hevc", False, "high", pix, hdr_params=params), pix)


class HdrX265ParamsTests(unittest.TestCase):
    """HDR10 static metadata → libx265 `-x265-params` string (physical → encoder units)."""

    # BT.2020 primaries, D65 white point, 1000-nit / 0.0001-nit mastering display.
    MASTERING = {"red_x": 0.708, "red_y": 0.292, "green_x": 0.170, "green_y": 0.797,
                 "blue_x": 0.131, "blue_y": 0.046, "white_point_x": 0.3127,
                 "white_point_y": 0.3290, "min_luminance": 0.0001, "max_luminance": 1000.0}

    def test_full_metadata_formats_master_display_and_cll(self):
        s = hdr_x265_params({"mastering_display": self.MASTERING,
                             "content_light": {"max_cll": 1000, "max_fall": 400}})
        # Chromaticity ×50000, luminance ×10000, in x265's G-B-R-WP-L order.
        self.assertEqual(
            s, "master-display=G(8500,39850)B(6550,2300)R(35400,14600)"
               "WP(15635,16450)L(10000000,1):max-cll=1000,400")

    def test_mastering_only_or_cll_only(self):
        self.assertEqual(hdr_x265_params({"mastering_display": None,
                                          "content_light": {"max_cll": 600, "max_fall": 120}}),
                         "max-cll=600,120")
        self.assertTrue(hdr_x265_params({"mastering_display": self.MASTERING,
                                         "content_light": None}).startswith("master-display="))

    def test_absent_metadata_is_none(self):
        self.assertIsNone(hdr_x265_params(None))
        self.assertIsNone(hdr_x265_params({}))
        self.assertIsNone(hdr_x265_params({"mastering_display": None, "content_light": None}))

    def test_deep_excludes_wide_chroma_but_high_includes_it(self):
        # is_deep_pix_fmt is bit-depth ONLY; 8-bit 4:2:2/4:4:4 is wide-chroma, not deep.
        for pf in ("yuv422p", "yuv444p"):
            self.assertFalse(is_deep_pix_fmt(pf), pf)
            self.assertTrue(is_high_bit_depth(pf), pf)   # still "high" (worth preserving)
        # Truly deep formats are both.
        for pf in ("yuv420p10le", "yuv422p10le", "p010le", "rgb48le"):
            self.assertTrue(is_deep_pix_fmt(pf), pf)
            self.assertTrue(is_high_bit_depth(pf), pf)


class ResolvePixFmtTests(unittest.TestCase):
    """Color-depth → output pixel format (the source-aware bit-depth decision)."""

    # Every planar YUV pixel format the bundled libx265 accepts — the encoder we drive for
    # high-bit-depth — so the tests can assert resolve_pix_fmt never emits an unencodable one.
    LIBX265_PLANAR = {
        "yuv420p", "yuvj420p", "yuv422p", "yuvj422p", "yuv444p", "yuvj444p",
        "yuv420p10le", "yuv422p10le", "yuv444p10le", "yuv420p12le", "yuv422p12le", "yuv444p12le"}

    def test_auto_preserves_standard_high_bit_depth_source_unchanged(self):
        # A source that's already a standard planar high-bit/wide-chroma format is matched
        # exactly (incl. its chroma + depth), with a note.
        for src in ("yuv420p10le", "yuv422p10le", "yuv444p10le", "yuv420p12le", "yuv422p"):
            pix, notes = resolve_pix_fmt("auto", src)
            self.assertEqual(pix, src, src)
            self.assertTrue(notes, src)   # the preserve is surfaced, never silent

    def test_auto_normalizes_exotic_source_to_encodable_keeping_chroma(self):
        # The fix: semi-planar / packed / RGB / alias sources are NOT passed through raw (the
        # encoder would reject them and fall back to 4:2:0) — they're normalized to the
        # encodable planar format that KEEPS their chroma + (clamped) bit depth.
        cases = {
            "nv16": "yuv422p", "nv61": "yuv422p", "nv24": "yuv444p", "nv42": "yuv444p",
            "gbrp": "yuv444p", "gbrap": "yuv444p", "yuyv422": "yuv422p", "uyvy422": "yuv422p",
            "p010le": "yuv420p10le", "p210le": "yuv422p10le", "p410le": "yuv444p10le",
            "x2rgb10le": "yuv444p10le", "rgb48le": "yuv444p12le", "rgba64le": "yuv444p12le",
            "yuv420p16le": "yuv420p12le",  # libx265 tops out at 12-bit
        }
        for src, want in cases.items():
            pix, notes = resolve_pix_fmt("auto", src)
            self.assertEqual(pix, want, src)
            self.assertIn(pix, self.LIBX265_PLANAR, f"{src} -> {pix} not encodable")
            self.assertTrue(notes, src)

    def test_9bit_source_maps_up_to_10bit_not_down_to_8(self):
        # 9-bit formats are >8-bit but no encoder has a 9-bit mode — they must round UP to
        # 10-bit (lossless), never fall through to 8-bit (the silent downgrade cubic flagged).
        for src in ("yuv420p9le", "yuv422p9le", "yuv444p9le", "gbrp9le", "yuv420p9be"):
            for mode in ("auto", "10"):
                pix = resolve_pix_fmt(mode, src)[0]
                self.assertTrue(is_deep_pix_fmt(pix), f"{mode}/{src} -> {pix}")
                self.assertEqual(pix[-4:], "10le", f"{mode}/{src} -> {pix}")  # 10-bit, never 8

    def test_depth_is_capped_to_the_encoder_ceiling(self):
        # H.264 (libx264) tops out at 10-bit and this VP9 build at 8-bit, so a deeper source
        # is capped to what the chosen encoder accepts — never handed a depth it would reject
        # and then fall back to 8-bit on. (HEVC/libx265 keeps 12-bit.)
        self.assertEqual(resolve_pix_fmt("auto", "yuv420p12le", "hevc")[0], "yuv420p12le")
        # A 12-bit source as H.264 lands at 10-bit — and SAYS so (not a false "preserved").
        for mode in ("auto", "10"):
            pix, notes = resolve_pix_fmt(mode, "yuv420p12le", "h264")
            self.assertEqual(pix, "yuv420p10le", mode)
            self.assertTrue(any("12-bit" in n and "10-bit" in n for n in notes), (mode, notes))
        # A 12-bit source that fits (HEVC) preserves — and is NOT mislabeled as a downgrade.
        _, hevc_notes = resolve_pix_fmt("auto", "yuv420p12le", "hevc")
        self.assertTrue(any("Preserving" in n for n in hevc_notes), hevc_notes)
        self.assertEqual(resolve_pix_fmt("auto", "yuv422p10le", "h264")[0], "yuv422p10le")
        # VP9 (this build) has no high bit depth at all → 8-bit, keeping chroma, and SAYS so.
        pix, notes = resolve_pix_fmt("auto", "yuv422p10le", "vp9")
        self.assertEqual(pix, "yuv422p")
        self.assertTrue(notes)                                  # the depth drop is surfaced
        # Force-10 on an encoder that can't do 10-bit lands at 8-bit with a note, not a lie.
        pix, notes = resolve_pix_fmt("10", "yuv420p", "vp9")
        self.assertEqual(pix, "yuv420p")
        self.assertTrue(any("8-bit" in n for n in notes))

    def test_resolved_format_is_always_encoder_safe(self):
        # Invariant across every mode × a broad spread of sources: the result is always a
        # libx265-encodable planar format (or 8-bit 4:2:0), never a raw semi-planar/packed one.
        srcs = ("yuv420p", "nv12", "nv16", "nv24", "gbrp", "yuyv422", "p010le", "p210le",
                "p410le", "rgb48le", "x2rgb10le", "yuv422p10le", "yuv420p16le", "")
        for mode in ("auto", "8", "10"):
            for src in srcs:
                pix = resolve_pix_fmt(mode, src)[0]
                self.assertIn(pix, self.LIBX265_PLANAR | {"yuv420p"}, f"{mode}/{src} -> {pix}")

    def test_auto_keeps_8bit_and_unknown_at_yuv420p(self):
        # Plain 8-bit and an unreadable/empty pix_fmt both stay the safe 8-bit 4:2:0 — no note.
        for src in ("yuv420p", "nv12", "yuvj420p", ""):
            pix, notes = resolve_pix_fmt("auto", src)
            self.assertEqual(pix, "yuv420p", src)
            self.assertEqual(notes, [], src)

    def test_force_8_always_yuv420p_and_notes_a_real_downgrade(self):
        pix, notes = resolve_pix_fmt("8", "yuv422p10le")
        self.assertEqual(pix, "yuv420p")
        self.assertTrue(notes)                     # crushing a 10-bit source is surfaced
        pix, notes = resolve_pix_fmt("8", "yuv420p")
        self.assertEqual(pix, "yuv420p")
        self.assertEqual(notes, [])                # 8-bit → 8-bit isn't a downgrade

    def test_force_10_upconverts_8bit_with_a_note(self):
        pix, notes = resolve_pix_fmt("10", "yuv420p")
        self.assertEqual(pix, TEN_BIT_PIX_FMT)     # yuv420p10le
        self.assertTrue(notes)                     # "no quality gain" warning surfaced
        # An unknown/empty source still yields a real 10-bit target.
        self.assertEqual(resolve_pix_fmt("10", "")[0], TEN_BIT_PIX_FMT)

    def test_force_10_on_8bit_wide_chroma_returns_a_real_10bit_format(self):
        # The bug: 8-bit 4:2:2/4:4:4 reads as "high" (wide chroma) but is NOT 10-bit, so
        # Force-10-bit must still bump it to a genuine 10-bit format that KEEPS its chroma
        # (any alias — planar yuvj*, packed yuyv/uyvy — not just yuv422p/yuv444p), never
        # falling through to 10-bit 4:2:0 (which would silently downgrade the chroma).
        for src, want in (("yuv422p", "yuv422p10le"), ("yuv444p", "yuv444p10le"),
                          ("yuvj422p", "yuv422p10le"), ("yuvj444p", "yuv444p10le"),
                          ("yuyv422", "yuv422p10le"), ("uyvy422", "yuv422p10le"),
                          # Named formats with no 444/422 in the name (semi-planar / GBR):
                          ("nv16", "yuv422p10le"), ("nv61", "yuv422p10le"),
                          ("nv24", "yuv444p10le"), ("gbrp", "yuv444p10le"),
                          ("gbrap", "yuv444p10le")):
            pix, notes = resolve_pix_fmt("10", src)
            self.assertEqual(pix, want, src)
            self.assertTrue(is_deep_pix_fmt(pix), pix)   # genuinely 10-bit now
            self.assertTrue(notes, src)                  # the upconvert is surfaced

    def test_force_10_preserves_an_already_deep_source(self):
        # Already ≥10-bit: keep the source format (incl. its chroma), don't coerce to 4:2:0.
        for src in ("yuv422p10le", "yuv444p10le", "yuv420p12le"):
            self.assertEqual(resolve_pix_fmt("10", src)[0], src, src)

    def test_force_10_always_yields_a_deep_target(self):
        # Whatever the 8-bit source, Force-10-bit must resolve to a true 10-bit+ format.
        for src in ("yuv420p", "nv12", "yuv422p", "yuv444p", "yuvj420p", ""):
            self.assertTrue(is_deep_pix_fmt(resolve_pix_fmt("10", src)[0]), src)

    def test_target_high_bit_depth_implies_software(self):
        # The render ladder keys "needs software encoder" off is_high_bit_depth(target);
        # every depth-preserving/forcing result must classify as high so it picks software.
        for mode, src in (("auto", "yuv420p10le"), ("10", "yuv420p"), ("10", "yuv422p10le")):
            self.assertTrue(is_high_bit_depth(resolve_pix_fmt(mode, src)[0]), (mode, src))
        # The 8-bit results must NOT (they keep the hardware fast path).
        for mode, src in (("auto", "yuv420p"), ("8", "yuv420p10le")):
            self.assertFalse(is_high_bit_depth(resolve_pix_fmt(mode, src)[0]), (mode, src))


if __name__ == "__main__":
    unittest.main()
