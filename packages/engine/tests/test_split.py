"""Tests for the split-track path/extension logic (no ffmpeg needed)."""

import unittest
from pathlib import Path

from crisp.split import split_paths


class SplitPathsTests(unittest.TestCase):
    def test_video_keeps_container_audio_is_m4a_for_aac(self):
        video, audio = split_paths("/x/clip_cleaned.mp4", "aac")
        self.assertEqual(video.name, "clip_cleaned_video.mp4")
        self.assertEqual(audio.name, "clip_cleaned_audio.m4a")

    def test_opus_audio_uses_opus_extension(self):
        video, audio = split_paths("/x/clip_cleaned.webm", "opus")
        self.assertEqual(video.name, "clip_cleaned_video.webm")
        self.assertEqual(audio.name, "clip_cleaned_audio.opus")

    def test_unknown_codec_falls_back_to_m4a(self):
        _, audio = split_paths("/x/c_cleaned.mkv", "weird")
        self.assertEqual(audio.name, "c_cleaned_audio.m4a")

    def test_stems_sit_beside_the_cleaned_file(self):
        # Compare Path to Path (not strings) so the separator stays the platform's own.
        video, audio = split_paths("/Users/me/out/clip_cleaned.mov", "aac")
        self.assertEqual(video.parent, Path("/Users/me/out"))
        self.assertEqual(audio.parent, Path("/Users/me/out"))
        self.assertEqual(video.name, "clip_cleaned_video.mov")

    def test_wav_format_overrides_codec_extension(self):
        # WAV is chosen regardless of the source audio codec; the video stem is
        # unaffected (still a stream copy in the original container).
        video, audio = split_paths("/x/clip_cleaned.mp4", "aac", "wav")
        self.assertEqual(audio.name, "clip_cleaned_audio.wav")
        self.assertEqual(video.name, "clip_cleaned_video.mp4")
        _, opus_audio = split_paths("/x/clip_cleaned.webm", "opus", "wav")
        self.assertEqual(opus_audio.name, "clip_cleaned_audio.wav")


if __name__ == "__main__":
    unittest.main()
