"""Preflight checks — fail fast before a long render."""

import unittest
from pathlib import Path
from unittest.mock import MagicMock, PropertyMock, patch

from crisp.errors import CleanError
from crisp.pipeline import _preflight_checks


def _make_meta(video_codec="h264", audio_channels=2, **overrides):
    meta = dict(width=1920, height=1080, fps_num=30, fps_den=1,
                audio_rate=48000, audio_channels=audio_channels,
                pix_fmt="yuv420p", color_primaries="", color_transfer="",
                color_space="", color_range="",
                video_codec=video_codec, audio_codec="aac")
    meta.update(overrides)
    return meta


def _mock_src(file_size=50_000_000):
    m = MagicMock(spec=Path)
    stat_mock = MagicMock(st_size=file_size)
    m.stat.return_value = stat_mock
    m.exists.return_value = True
    return m


def _mock_out(parent=None):
    m = MagicMock(spec=Path)
    m.parent = parent or Path("/media/out")
    return m


class PreflightStreamChecks(unittest.TestCase):
    """Video/audio stream validation via probe_stream_meta."""

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_passes_on_valid_source(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.return_value.free = 500_000_000
        _preflight_checks(_mock_src(), _mock_out(), duration=60.0)

    @patch("crisp.pipeline.probe_stream_meta")
    def test_fails_when_probe_returns_none(self, probe_stream_meta):
        probe_stream_meta.return_value = None
        with self.assertRaises(CleanError) as cm:
            _preflight_checks(_mock_src(), _mock_out(), duration=60.0)
        self.assertIn("Could not read video properties", str(cm.exception))

    @patch("crisp.pipeline.probe_stream_meta")
    def test_fails_on_empty_video_codec(self, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta(video_codec="")
        with self.assertRaises(CleanError) as cm:
            _preflight_checks(_mock_src(), _mock_out(), duration=60.0)
        self.assertIn("video codec", str(cm.exception).lower())

    @patch("crisp.pipeline.probe_stream_meta")
    def test_fails_on_no_audio_stream(self, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta(audio_channels=0)
        with self.assertRaises(CleanError) as cm:
            _preflight_checks(_mock_src(), _mock_out(), duration=60.0)
        self.assertIn("No audio stream", str(cm.exception))

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_fails_on_insufficient_disk(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.return_value.free = 1_000_000
        with self.assertRaises(CleanError) as cm:
            _preflight_checks(_mock_src(file_size=50_000_000), _mock_out(), duration=60.0)
        self.assertIn("disk space", str(cm.exception).lower())

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_skips_disk_check_on_oserror(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.side_effect = OSError
        _preflight_checks(_mock_src(), _mock_out(), duration=60.0)
