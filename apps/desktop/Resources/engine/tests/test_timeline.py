"""FCPXML editor-handoff generation — frame-exact times + valid structure."""

import unittest
from xml.dom import minidom

from crisp.errors import CleanError
from crisp.timeline import (
    FCPXML_VERSION, build_fcpxml, fcpxml_colorspace, frame_time, project_paths,
    secs_to_frames, timeline_seconds,
)
from crisp.tools import parse_stream_meta


class FrameTimeTests(unittest.TestCase):
    def test_integer_rate_reduces(self):
        # 60fps: a frame is 1/60s; 90 frames = 90/60 = 3/2 s.
        self.assertEqual(frame_time(1, 60, 1), "1/60s")
        self.assertEqual(frame_time(90, 60, 1), "3/2s")
        self.assertEqual(frame_time(120, 60, 1), "2s")        # whole second drops denom

    def test_ntsc_rate(self):
        # 29.97 = 30000/1001: a frame is 1001/30000 s.
        self.assertEqual(frame_time(1, 30000, 1001), "1001/30000s")

    def test_secs_to_frames_rounds(self):
        self.assertEqual(secs_to_frames(1.0, 60, 1), 60)
        self.assertEqual(secs_to_frames(0.49, 60, 1), 29)     # 29.4 → 29


class BuildFcpxmlTests(unittest.TestCase):
    def _doc(self, **over):
        args = dict(media_uri="file:///x/original.mov", name="clip", num=60, den=1,
                    width=1660, height=1080, audio_rate=48000, audio_channels=2,
                    duration=90.0, keep=[(0.0, 3.0), (5.5, 9.2)])
        args.update(over)
        return build_fcpxml(**args)

    def test_well_formed_and_versioned(self):
        xml = self._doc()
        dom = minidom.parseString(xml)            # raises if not well-formed
        self.assertEqual(dom.documentElement.getAttribute("version"), FCPXML_VERSION)

    def test_one_asset_clip_per_kept_segment(self):
        dom = minidom.parseString(self._doc(keep=[(0, 1), (2, 3), (4, 5)]))
        self.assertEqual(len(dom.getElementsByTagName("asset-clip")), 3)

    def test_all_times_are_frame_aligned(self):
        # Every offset/start/duration must be an exact integer number of frames.
        num, den = 30000, 1001
        dom = minidom.parseString(self._doc(num=num, den=den,
                                            keep=[(0.0, 2.0), (3.3, 7.77), (10.0, 10.5)]))
        frame_secs = den / num
        checked = 0
        for clip in dom.getElementsByTagName("asset-clip"):
            for attr in ("offset", "start", "duration"):
                val = clip.getAttribute(attr)
                self.assertTrue(val.endswith("s"))
                body = val[:-1]
                n, d = (body.split("/", 1) + ["1"])[:2]
                frames = (int(n) / int(d)) / frame_secs
                self.assertAlmostEqual(frames, round(frames), places=6,
                                       msg=f"{attr}={val} is not frame-aligned")
                checked += 1
        self.assertGreater(checked, 0)

    def test_segments_lie_back_to_back(self):
        # The Nth clip's offset equals the sum of prior durations (no gaps/overlaps).
        dom = minidom.parseString(self._doc(num=60, den=1,
                                            keep=[(0.0, 1.0), (4.0, 5.5), (8.0, 8.5)]))
        clips = dom.getElementsByTagName("asset-clip")
        # 60fps: durations 60, 90, 30 frames → offsets 0, 60, 150 frames.
        self.assertEqual(clips[0].getAttribute("offset"), "0s")
        self.assertEqual(clips[1].getAttribute("offset"), frame_time(60, 60, 1))
        self.assertEqual(clips[2].getAttribute("offset"), frame_time(150, 60, 1))

    def test_media_uri_and_name_are_present(self):
        xml = self._doc(media_uri="file:///a%20b/clip.mov", name="My Clip")
        self.assertIn('src="file:///a%20b/clip.mov"', xml)
        self.assertIn("My Clip", xml)

    def test_xml_special_chars_escaped(self):
        # An ampersand in the name must not break the document; the parser unescapes
        # it back to the literal value.
        dom = minidom.parseString(self._doc(name="A & B"))
        asset = dom.getElementsByTagName("asset")[0]
        self.assertEqual(asset.getAttribute("name"), "A & B")

    def test_quotes_in_name_are_attribute_escaped(self):
        # A double quote in the name must not break the (quoted) XML attribute.
        dom = minidom.parseString(self._doc(name='My "Best" Take'))
        self.assertEqual(dom.getElementsByTagName("asset")[0].getAttribute("name"),
                         'My "Best" Take')

    def test_drop_frame_only_for_ntsc_30_60(self):
        # 29.97 / 59.94 are drop-frame; 23.976 (24000/1001) is NOT.
        self.assertIn('tcFormat="DF"', self._doc(num=30000, den=1001))
        self.assertIn('tcFormat="DF"', self._doc(num=60000, den=1001))
        self.assertIn('tcFormat="NDF"', self._doc(num=24000, den=1001))
        self.assertIn('tcFormat="NDF"', self._doc(num=60, den=1))

    def test_audio_layout_tracks_channel_count(self):
        self.assertIn('audioLayout="mono"', self._doc(audio_channels=1))
        self.assertIn('audioLayout="stereo"', self._doc(audio_channels=2))
        self.assertIn('audioLayout="surround"', self._doc(audio_channels=6))

    def test_no_audio_source_omits_audio(self):
        # A source with no audio (channels 0) must not declare a phantom track.
        xml = self._doc(audio_channels=0)
        dom = minidom.parseString(xml)
        self.assertEqual(dom.getElementsByTagName("asset")[0].getAttribute("hasAudio"), "0")
        self.assertNotIn("audioChannels", xml)
        self.assertNotIn("audioLayout", xml)

    def test_has_audio_false_overrides(self):
        self.assertIn('hasAudio="0"', self._doc(audio_channels=2, has_audio=False))

    def test_audio_rate_tokens_and_fallback(self):
        self.assertIn('audioRate="32k"', self._doc(audio_rate=32000))      # exact token
        self.assertIn('audioRate="44.1k"', self._doc(audio_rate=44100))    # exact token
        # Non-token rates snap to the NEAREST valid token, not a blanket 48k.
        self.assertIn('audioRate="32k"', self._doc(audio_rate=24000))      # 24k → 32k (nearest)
        self.assertIn('audioRate="48k"', self._doc(audio_rate=50000))      # 50k → 48k (nearest)
        self.assertIn('audioRate="192k"', self._doc(audio_rate=999999))    # huge → highest token

    def test_clip_clamped_to_asset_duration(self):
        # keep extends past the asset length → the clip must not exceed it (no
        # "media out of range" in the editor).
        dom = minidom.parseString(self._doc(num=60, den=1, duration=1.0, keep=[(0.0, 2.0)]))
        self.assertEqual(dom.getElementsByTagName("asset-clip")[0].getAttribute("duration"),
                         frame_time(60, 60, 1))   # clamped to 60 frames = 1s

    def test_empty_keep_raises(self):
        with self.assertRaises(CleanError):
            self._doc(keep=[])

    def test_sub_frame_segments_dropped_then_empty_raises(self):
        # A span shorter than a frame collapses to 0 frames; all-collapsed → raises.
        with self.assertRaises(CleanError):
            self._doc(num=60, den=1, keep=[(0.0, 0.001)])

    def test_unknown_fps_raises(self):
        with self.assertRaises(CleanError):
            self._doc(num=0, den=0)


class TimelineSecondsTests(unittest.TestCase):
    def test_snaps_to_frame_grid(self):
        # 1.008s at 60fps rounds to 60 frames = 1.0s, not the raw 1.008s span.
        self.assertAlmostEqual(timeline_seconds([(0.0, 1.008)], 60, 1), 1.0, places=6)

    def test_sums_multiple_clips(self):
        self.assertAlmostEqual(timeline_seconds([(0.0, 1.0), (2.0, 3.5)], 60, 1), 2.5, places=6)

    def test_unknown_rate_falls_back_to_raw_sum(self):
        self.assertAlmostEqual(timeline_seconds([(0.0, 1.0), (2.0, 3.5)], 0, 0), 2.5, places=6)


class ProjectPathsTests(unittest.TestCase):
    def test_beside_source(self):
        proj, media, fcpxml = project_paths("/v/talk.mov")
        self.assertEqual(str(proj), "/v/talk (Crisp)")
        self.assertEqual(str(media), "/v/talk (Crisp)/talk.mov")
        self.assertEqual(str(fcpxml), "/v/talk (Crisp)/talk.fcpxml")

    def test_in_out_dir(self):
        proj, media, fcpxml = project_paths("/v/talk.mkv", out_dir="/out")
        self.assertEqual(str(proj), "/out/talk (Crisp)")
        self.assertEqual(str(media), "/out/talk (Crisp)/talk.mkv")


class ColorSpaceTests(unittest.TestCase):
    def test_sdr_and_unknown_default_to_rec709(self):
        self.assertEqual(fcpxml_colorspace("bt709", "bt709"), "1-1-1 (Rec. 709)")
        self.assertEqual(fcpxml_colorspace("", ""), "1-1-1 (Rec. 709)")
        self.assertEqual(fcpxml_colorspace("smpte170m", "bt709"), "1-1-1 (Rec. 709)")

    def test_hdr_is_not_mistagged_as_709(self):
        self.assertEqual(fcpxml_colorspace("bt2020", "smpte2084"), "9-16-9 (Rec. 2020 PQ)")
        self.assertEqual(fcpxml_colorspace("bt2020", "arib-std-b67"), "9-18-9 (Rec. 2020 HLG)")
        self.assertEqual(fcpxml_colorspace("bt2020", "bt2020-10"), "9-16-9 (Rec. 2020)")

    def test_colorspace_flows_into_format(self):
        xml = build_fcpxml(media_uri="m.mov", name="c", num=30, den=1, width=1920, height=1080,
                           audio_rate=48000, audio_channels=0, duration=2.0, keep=[(0.0, 1.0)],
                           has_audio=False, color_space="9-16-9 (Rec. 2020 PQ)")
        self.assertIn('colorSpace="9-16-9 (Rec. 2020 PQ)"', xml)


class TimelineSecondsClampTests(unittest.TestCase):
    def test_clamps_to_asset_duration_like_build(self):
        # keep runs to 2.0s but the media is only 1.0s (60 frames @ 60fps): the reported
        # snapped length must match the clamped timeline (1.0s), not the raw 2.0s span.
        self.assertEqual(timeline_seconds([(0.0, 2.0)], 60, 1, duration=1.0), 1.0)
        # Without a duration cap it's the raw frame sum (back-compat).
        self.assertEqual(timeline_seconds([(0.0, 2.0)], 60, 1), 2.0)


class ParseStreamMetaTests(unittest.TestCase):
    """A total probe failure must return None (so the handoff fails loud) rather than
    fabricate 1920x1080/30fps — a wrong fps in the FCPXML lands every cut at the wrong
    source time. Individual missing fields still default."""

    VIDEO = '{"codec_type":"video","width":3840,"height":2160,"r_frame_rate":"30000/1001"}'
    AUDIO = '{"codec_type":"audio","sample_rate":"44100","channels":"1"}'

    def _json(self, *streams):
        return '{"streams":[' + ",".join(streams) + "]}"

    def test_good_probe_reads_real_values(self):
        meta = parse_stream_meta(0, self._json(self.VIDEO, self.AUDIO))
        self.assertEqual((meta["width"], meta["height"]), (3840, 2160))
        self.assertEqual((meta["fps_num"], meta["fps_den"]), (30000, 1001))
        self.assertEqual((meta["audio_rate"], meta["audio_channels"]), (44100, 1))

    def test_nonzero_exit_is_failure(self):
        self.assertIsNone(parse_stream_meta(1, self._json(self.VIDEO)))

    def test_malformed_json_is_failure(self):
        self.assertIsNone(parse_stream_meta(0, "not json{"))

    def test_no_video_stream_is_failure(self):
        # Audio-only / metadata-only: can't build a video timeline — signal failure, not
        # a fabricated 30fps asset.
        self.assertIsNone(parse_stream_meta(0, self._json(self.AUDIO)))

    def test_valid_but_non_object_json_is_failure(self):
        # Valid JSON that isn't the expected shape must fail cleanly, not crash on .get.
        for body in ("null", "5", "[1,2,3]", '"hi"'):
            self.assertIsNone(parse_stream_meta(0, body), body)

    def test_unreadable_frame_rate_is_failure(self):
        # A video stream with no / zero r_frame_rate must FAIL (fps is required) rather than
        # default to 30fps and misplace every cut.
        self.assertIsNone(parse_stream_meta(0, self._json('{"codec_type":"video","width":1280,"height":720}')))
        self.assertIsNone(parse_stream_meta(0, self._json('{"codec_type":"video","r_frame_rate":"0/0"}')))

    def test_missing_size_defaults_when_fps_known(self):
        # fps present but no width/height → those default (less critical), still usable.
        meta = parse_stream_meta(0, self._json('{"codec_type":"video","r_frame_rate":"24/1"}'))
        self.assertEqual((meta["fps_num"], meta["fps_den"]), (24, 1))
        self.assertEqual((meta["width"], meta["height"]), (1920, 1080))
        self.assertEqual(meta["audio_channels"], 0)   # no audio stream → 0, no phantom track

    def test_audio_channels_default_to_stereo_when_unparseable(self):
        meta = parse_stream_meta(0, self._json(self.VIDEO, '{"codec_type":"audio"}'))
        self.assertEqual(meta["audio_channels"], 2)   # stream exists but channels missing


if __name__ == "__main__":
    unittest.main()
