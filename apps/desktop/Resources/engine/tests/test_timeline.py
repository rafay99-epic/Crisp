"""FCPXML editor-handoff generation — frame-exact times + valid structure."""

import unittest
from xml.dom import minidom

from crisp.errors import CleanError
from crisp.timeline import (
    FCPXML_VERSION, build_fcpxml, frame_time, project_paths, secs_to_frames, timeline_seconds,
)


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
        self.assertIn('audioRate="32k"', self._doc(audio_rate=32000))
        self.assertIn('audioRate="48k"', self._doc(audio_rate=999999))   # unknown → 48k

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


if __name__ == "__main__":
    unittest.main()
