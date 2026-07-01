"""Tests for the engine's file logger (crisp.enginelog).

Pure I/O against a temp dir — no ffmpeg/whisper. Mirrors the other suites:
unittest + tempfile, inline expectations.
"""

import re
import unittest
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory

from crisp.enginelog import EngineLogger, logger_from_env

# The shared Swift/Python line shape: "<ts>  <LEVEL>  [<category>]  <text>".
# Every physical line a record produces must match this so a merged timeline
# (engine + app, interleaved) parses uniformly.
LINE_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}  [A-Z]+ +\[engine[^\]]*\]  ")


class NoOpLoggerTests(unittest.TestCase):
    def test_disabled_without_dir(self):
        log = EngineLogger(None)
        self.assertFalse(log.enabled)
        # Every method must be a safe no-op when no directory is configured.
        log.info("nothing")
        log.error("nothing")
        log.command("ffmpeg", ["a", "b"])
        log.tool_result("ffmpeg", 1, "boom")  # must not raise

    def test_logger_from_env_uses_env(self):
        import os
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            prev = os.environ.get("CRISP_LOG_DIR")
            os.environ["CRISP_LOG_DIR"] = d
            try:
                log = logger_from_env(tag="clip.mp4")
                self.assertTrue(log.enabled)
                self.assertEqual(log.dir, Path(d))
            finally:
                if prev is None:
                    del os.environ["CRISP_LOG_DIR"]
                else:
                    os.environ["CRISP_LOG_DIR"] = prev


class FileWriteTests(unittest.TestCase):
    def _today_file(self, d):
        return Path(d) / f"{date.today().isoformat()}.log"

    def test_writes_daily_file_with_format(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d, tag="clip.mp4")
            log.info("hello world")
            text = self._today_file(d).read_text()
            self.assertIn("INFO", text)
            self.assertIn("hello world", text)
            # category carries the tag and pid so interleaved runs stay attributable
            self.assertIn(f"[engine:clip.mp4#{log.pid}]", text)

    def test_appends_multiple_lines(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.info("first")
            log.error("second")
            lines = self._today_file(d).read_text().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertIn("first", lines[0])
            self.assertIn("ERROR", lines[1])
            self.assertIn("second", lines[1])

    def test_creates_missing_directory(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            nested = Path(d) / "logs"
            log = EngineLogger(nested)
            self.assertTrue(nested.exists())
            log.info("ok")
            self.assertTrue((nested / f"{date.today().isoformat()}.log").exists())

    def _assert_every_line_well_formed(self, path):
        """Each physical line must carry the shared timestamp/level/category prefix
        — even continuation lines of a multi-line record — so a merged engine+app
        timeline parses uniformly."""
        lines = path.read_text().splitlines()
        self.assertTrue(lines)
        for ln in lines:
            self.assertRegex(ln, LINE_RE)

    def test_tool_result_logs_stderr_on_failure(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.tool_result("ffmpeg render", 1, "Invalid data found\nmoov atom not found")
            text = self._today_file(d).read_text()
            self.assertIn("ERROR", text)
            self.assertIn("ffmpeg render exited 1", text)
            self.assertIn("Invalid data found", text)
            # The multi-line stderr block must stay one-prefixed-line-per-record.
            self._assert_every_line_well_formed(self._today_file(d))

    def test_tool_result_quiet_on_success(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.tool_result("ffmpeg render", 0, "noise we don't care about")
            text = self._today_file(d).read_text()
            self.assertIn("ffmpeg render exited 0", text)
            self.assertNotIn("noise we don't care about", text)
            self.assertNotIn("ERROR", text)

    def test_reuses_one_descriptor_across_writes(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.info("first")
            fd_after_first = log._fd
            self.assertGreaterEqual(fd_after_first, 0)
            log.info("second")
            # Same cached descriptor — not reopened per line.
            self.assertEqual(log._fd, fd_after_first)
            self.assertEqual(len(self._today_file(d).read_text().splitlines()), 2)

    def test_reopens_after_close(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.info("before close")
            log.close()
            self.assertEqual(log._fd, -1)
            log.info("after close")  # must transparently reopen
            lines = self._today_file(d).read_text().splitlines()
            self.assertEqual(len(lines), 2)
            self.assertIn("before close", lines[0])
            self.assertIn("after close", lines[1])

    def test_command_is_shell_quoted(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            log.command("ffmpeg", ["ffmpeg", "-i", "my video.mp4"])
            text = self._today_file(d).read_text()
            self.assertIn("'my video.mp4'", text)

    def test_exception_records_traceback(self):
        with TemporaryDirectory(ignore_cleanup_errors=True) as d:
            log = EngineLogger(d)
            try:
                raise ValueError("kaboom")
            except ValueError:
                log.exception("Unexpected error")
            text = self._today_file(d).read_text()
            self.assertIn("Unexpected error", text)
            self.assertIn("Traceback", text)
            self.assertIn("kaboom", text)
            # A traceback spans many lines; each must keep the record prefix.
            self._assert_every_line_well_formed(self._today_file(d))


if __name__ == "__main__":
    unittest.main()
