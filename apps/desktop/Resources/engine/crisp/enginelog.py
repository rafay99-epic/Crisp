"""File logging for the engine.

The desktop app drives this engine as a subprocess, and when something fails deep
inside ffmpeg or whisper the NDJSON status stream isn't enough to debug from — the
real detail (the exact command, the tool's stderr) used to be discarded. This
writes that detail to an append-only daily file shared with the Swift app
(`~/.crisp*/logs/<yyyy-MM-dd>.log`), so one timeline covers the whole clean.

The log directory is handed to us by the app via the ``CRISP_LOG_DIR`` env var (or
``--log-dir``); the bare ``python3 clean_video.py …`` CLI may pass one too. With
none set, every method is a no-op — library users and the plain CLI keep their old
behavior, nothing is written.

Each line is a single ``os.write()`` of one whole line in ``O_APPEND`` mode, which
POSIX makes atomic for line-sized writes. So several parallel cleans (and the Swift
app) can append to the same daily file without a lock and without tearing lines.
The line format mirrors the Swift `FileLog` so both sides read uniformly.
"""

import os
import shlex
import time
import traceback
from datetime import date
from pathlib import Path


class EngineLogger:
    """Append-only logger to a per-day file, or a no-op when no directory is set."""

    def __init__(self, log_dir, tag=""):
        self.dir = None
        self.tag = tag
        self.pid = os.getpid()
        if log_dir:
            try:
                d = Path(log_dir).expanduser()
                d.mkdir(parents=True, exist_ok=True)
                self.dir = d
            except OSError:
                self.dir = None  # logging must never break a clean

    @property
    def enabled(self):
        return self.dir is not None

    def _path(self):
        return self.dir / f"{date.today().isoformat()}.log"

    def log(self, level, message):
        if self.dir is None:
            return
        now = time.time()
        stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)) + f".{int((now % 1) * 1000):03d}"
        # The pid disambiguates lines when several cleans interleave in one file;
        # the tag (input filename) says which clean this line belongs to.
        cat = f"engine:{self.tag}#{self.pid}" if self.tag else f"engine#{self.pid}"
        prefix = f"{stamp}  {level:<6}  [{cat}]  "
        # One prefixed physical line per record line: a multi-line message (a
        # traceback, an ffmpeg stderr block) stays greppable and keeps the same
        # self-describing shape as the Swift FileLog, so a merged timeline parses
        # uniformly. The whole block is a single os.write() so it still appends
        # atomically against the other processes sharing this file.
        block = "".join(f"{prefix}{ln}\n" for ln in str(message).split("\n"))
        try:
            # 0o600: the log holds filenames, command args, and tool stderr — keep
            # it readable only by the user who owns it.
            fd = os.open(str(self._path()), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
            try:
                os.write(fd, block.encode("utf-8", "replace"))
            finally:
                os.close(fd)
        except OSError:
            pass  # never let a logging failure surface as a clean failure

    def debug(self, message):
        self.log("DEBUG", message)

    def info(self, message):
        self.log("INFO", message)

    def notice(self, message):
        self.log("NOTICE", message)

    def error(self, message):
        self.log("ERROR", message)

    def exception(self, prefix="Unhandled error"):
        """Log the current exception with its full traceback."""
        self.error(f"{prefix}:\n{traceback.format_exc().rstrip()}")

    def command(self, label, argv):
        """Record a subprocess command line (copy-pasteable) before it runs."""
        self.debug(f"{label}: {' '.join(shlex.quote(str(a)) for a in argv)}")

    def tool_result(self, label, returncode, stderr=""):
        """Record how an external tool exited, with its stderr tail. Logs at ERROR
        on a nonzero exit, DEBUG otherwise — so a healthy run stays quiet but a
        failure carries everything needed to diagnose it."""
        failed = returncode != 0
        message = f"{label} exited {returncode}"
        tail = (stderr or "").strip()
        # Only attach the tool's stderr when it actually failed — a healthy run's
        # banner/diagnostics would just be noise.
        if failed and tail:
            message += f"\n--- {label} stderr ---\n{tail[-2000:]}\n--- end {label} stderr ---"
        self.log("ERROR" if failed else "DEBUG", message)


def logger_from_env(log_dir=None, tag=""):
    """Build an `EngineLogger` from an explicit dir or the ``CRISP_LOG_DIR`` env
    var (what the Swift app sets). Returns a no-op logger when neither is present."""
    return EngineLogger(log_dir or os.environ.get("CRISP_LOG_DIR"), tag=tag)
