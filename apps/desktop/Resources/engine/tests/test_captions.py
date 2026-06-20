"""Unit tests for caption export (crisp.captions).

Pure logic only — no ffmpeg/whisper. Re-timing + SRT/VTT formatting + cue grouping.
"""

import unittest

from crisp import captions


def word(text, start, end):
    return {"text": text, "start": start, "end": end}


class OriginalToCleanedTests(unittest.TestCase):
    def test_maps_across_cut(self):
        keep = [(0.0, 2.0), (5.0, 8.0)]
        # Inside the first kept segment → unchanged.
        self.assertAlmostEqual(captions.original_to_cleaned(1.0, keep), 1.0)
        # Inside the second kept segment → shifted left by the removed 2..5 gap.
        self.assertAlmostEqual(captions.original_to_cleaned(6.0, keep), 3.0)
        # A time inside the removed gap clamps to the start of the next kept segment.
        self.assertAlmostEqual(captions.original_to_cleaned(3.5, keep), 2.0)

    def test_after_last_segment(self):
        keep = [(0.0, 2.0)]
        self.assertAlmostEqual(captions.original_to_cleaned(9.0, keep), 2.0)


class RetimeWordsTests(unittest.TestCase):
    def test_drops_fillers_and_retimes(self):
        keep = [(0.0, 2.0), (5.0, 8.0)]
        words = [
            word(" Hello", 0.2, 0.8),
            word(" um", 1.0, 1.4),       # filler → dropped
            word(" world", 6.0, 6.5),    # in second segment → shifts to ~3.0
        ]
        out = captions.retime_words(words, keep)
        self.assertEqual([w["text"] for w in out], ["Hello", "world"])  # leading space stripped, filler gone
        self.assertAlmostEqual(out[0]["start"], 0.2)
        self.assertAlmostEqual(out[1]["start"], 3.0)

    def test_skips_word_in_removed_region(self):
        keep = [(0.0, 2.0), (5.0, 8.0)]
        words = [word(" gone", 3.0, 3.4)]   # entirely inside the 2..5 cut
        self.assertEqual(captions.retime_words(words, keep), [])


class FormattingTests(unittest.TestCase):
    def test_srt_timestamp_and_structure(self):
        cues = [{"start": 0.0, "end": 1.5, "lines": ["Hello world"]}]
        srt = captions.to_srt(cues)
        self.assertIn("1\r\n", srt)
        self.assertIn("00:00:00,000 --> 00:00:01,500", srt)
        self.assertTrue(srt.endswith("\r\n"))
        self.assertIn("Hello world", srt)

    def test_vtt_header_and_period_separator(self):
        cues = [{"start": 61.25, "end": 62.0, "lines": ["Hi"]}]
        vtt = captions.to_vtt(cues)
        self.assertTrue(vtt.startswith("WEBVTT\n\n"))
        self.assertIn("00:01:01.250 --> 00:01:02.000", vtt)

    def test_vtt_escapes_markup(self):
        cues = [{"start": 0.0, "end": 1.0, "lines": ["a < b & c"]}]
        self.assertIn("a &lt; b &amp; c", captions.to_vtt(cues))

    def test_empty_cues_yield_empty_srt(self):
        self.assertEqual(captions.to_srt([]), "")


class CueGroupingTests(unittest.TestCase):
    def test_splits_on_sentence_end(self):
        words = [word("Hi.", 0.0, 0.4), word("Next", 0.5, 0.9)]
        cues = captions.group_into_cues(words)
        self.assertEqual(len(cues), 2)

    def test_splits_on_long_pause(self):
        words = [word("one", 0.0, 0.4), word("two", 3.0, 3.4)]  # 2.6s gap > 0.5
        self.assertEqual(len(captions.group_into_cues(words)), 2)

    def test_wraps_long_lines(self):
        # 6 words of ~9 chars each → >42 chars, wraps to 2 lines, stays one cue.
        ws = [word("wordwords", i * 0.3, i * 0.3 + 0.25) for i in range(6)]
        cues = captions.group_into_cues(ws)
        self.assertEqual(len(cues), 1)
        self.assertGreaterEqual(len(cues[0]["lines"]), 2)
        self.assertTrue(all(len(line) <= captions.MAX_CHARS_PER_LINE for line in cues[0]["lines"]))

    def test_short_cue_is_stretched_to_min_duration(self):
        cues = captions.group_into_cues([word("Hi.", 0.0, 0.3)])
        self.assertGreaterEqual(cues[0]["end"] - cues[0]["start"], captions.MIN_CUE_DUR - 1e-6)


class PathTests(unittest.TestCase):
    def test_caption_paths(self):
        srt, vtt = captions.caption_paths("/out/clip_cleaned.mp4")
        self.assertEqual(srt.name, "clip_cleaned.srt")
        self.assertEqual(vtt.name, "clip_cleaned.vtt")


if __name__ == "__main__":
    unittest.main()
