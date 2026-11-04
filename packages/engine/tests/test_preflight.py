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

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_analyze_mode_uses_tempdir(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.return_value.free = 500_000_000
        _preflight_checks(_mock_src(), _mock_out(), duration=60.0, analyze_only=True)
        out_dir_arg = disk_usage.call_args[0][0]
        import tempfile
        self.assertEqual(out_dir_arg, Path(tempfile.gettempdir()))

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_analyze_mode_lower_disk_need(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.return_value.free = 5_000_000
        # This would fail under will_backup=True (need ≈50MB + WAV > 5MB free),
        # but analyze_only only budgets the WAV (~1.7 MB for 10s) so it passes.
        _preflight_checks(_mock_src(file_size=50_000_000), _mock_out(), duration=10.0, analyze_only=True)

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_render_without_backup_uses_outdir(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta()
        disk_usage.return_value.free = 500_000_000
        _preflight_checks(_mock_src(), _mock_out(parent=Path("/media/out")),
                          duration=60.0, will_backup=False, analyze_only=False)
        out_dir_arg = disk_usage.call_args[0][0]
        self.assertEqual(out_dir_arg, Path("/media/out"))

    @patch("crisp.pipeline.probe_stream_meta")
    @patch("crisp.pipeline.shutil.disk_usage")
    def test_preflight_returns_meta(self, disk_usage, probe_stream_meta):
        probe_stream_meta.return_value = _make_meta(video_codec="hevc")
        disk_usage.return_value.free = 500_000_000
        meta = _preflight_checks(_mock_src(), _mock_out(), duration=60.0)
        self.assertEqual(meta["video_codec"], "hevc")
        self.assertEqual(meta["audio_channels"], 2)
