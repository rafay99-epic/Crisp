"""Fail-fast hardening: a tool failure must surface as a CleanError, never as a
"successful" clean that silently did the wrong thing (cut nothing, dropped spans)."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from crisp.detect import detect_silences, filler_words
from crisp.errors import CleanError
from crisp.pipeline import clean_video


# CI runners have no ffmpeg (this suite is stdlib-only by design), so the binary
# resolver must be mocked alongside subprocess.run — otherwise ffmpeg_bin() raises
# its own "ffmpeg not found" CleanError first and the assertions pass (or fail)
# for the wrong reason.
@mock.patch("crisp.detect.ffmpeg_bin", return_value="ffmpeg")
class DetectSilencesFailFast(unittest.TestCase):
    @mock.patch("crisp.detect.subprocess.run")
    def test_nonzero_exit_raises_instead_of_no_pauses(self, run, _bin):
        # A failed silencedetect used to return [] — the clean then "succeeded"
        # as a full re-encode that cut nothing.
        run.return_value = mock.Mock(returncode=1, stdout="", stderr="boom")
        with self.assertRaises(CleanError) as cm:
            detect_silences(Path("x.wav"), -30, 0.05, on_log=lambda m: None)
        self.assertIn("Pause detection failed", str(cm.exception))

    @mock.patch("crisp.detect.subprocess.run")
    def test_zero_exit_parses_normally(self, run, _bin):
        run.return_value = mock.Mock(returncode=0, stdout="", stderr=(
            "[silencedetect] silence_start: 1.5\n"
            "[silencedetect] silence_end: 3.0 | silence_duration: 1.5\n"))
        got = detect_silences(Path("x.wav"), -30, 0.05, on_log=lambda m: None)
        self.assertEqual(got, [(1.5, 3.0)])


class FillerOutputValidation(unittest.TestCase):
    """The Core ML helper's JSON is validated as one shape — anything malformed
    becomes a CleanError, not a raw AttributeError/unpack traceback."""

    def _run(self, stdout):
        with tempfile.TemporaryDirectory() as d:
            model = Path(d) / "m.mlmodel"
            model.write_bytes(b"x")
            wav = Path(d) / "a.wav"
            wav.write_bytes(b"\0" * 320)
            with mock.patch("crisp.detect.subprocess.run") as run:
                run.return_value = mock.Mock(returncode=0, stdout=stdout, stderr="")
                return filler_words("bin", str(model), wav,
                                    lambda m: None, lambda f, label="": None)

    def test_valid_spans_parse(self):
        words = self._run('{"fillers": [[1.0, 1.5]]}')
        self.assertEqual(words, [{"text": "um", "start": 1.0, "end": 1.5}])

    def test_top_level_array_is_clean_error(self):
        with self.assertRaises(CleanError):
            self._run("[1, 2]")

    def test_missing_fillers_list_is_clean_error(self):
        with self.assertRaises(CleanError):
            self._run('{"fillers": "nope"}')

    def test_malformed_span_is_clean_error(self):
        with self.assertRaises(CleanError):
            self._run('{"fillers": [[1.0]]}')


class OutputEqualsSourceRefused(unittest.TestCase):
    """An explicit out_path pointing at the source must be refused before any
    work starts — render() ends in os.replace(part, out_path), which would
    destroy the original."""

    def test_out_path_equal_to_src_raises(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "clip.mp4"
            src.write_bytes(b"x")
            with self.assertRaises(CleanError) as cm:
                clean_video(src, out_path=src)
            self.assertIn("same as the source", str(cm.exception))

    def test_out_path_hardlink_to_src_raises(self):
        # A different path to the same inode (hardlink; also the shape of a
        # case-variant path on a case-insensitive filesystem) must be refused too.
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "clip.mp4"
            src.write_bytes(b"x")
            link = Path(d) / "alias.mp4"
            os.link(src, link)
            with self.assertRaises(CleanError) as cm:
                clean_video(src, out_path=link)
            self.assertIn("same as the source", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
