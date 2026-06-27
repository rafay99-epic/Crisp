"""`crisp.semantic` — the bridge to the crisp-embed helper.

These drive the real subprocess path against a fake `crisp-embed` (a tiny Python
script), covering the degradation code that's most likely to face garbage from a
future model: bad exit codes, unparseable / non-finite / mistyped / wrong-count
output, a missing binary, and a hang. The contract is "only ever adds precision,
never breaks a clean" — so every failure must degrade to judge=None, never raise."""

import os
import stat
import tempfile
import textwrap
import unittest

from crisp import semantic
from crisp.retake import detect_retakes


def seq(words, *, dur=0.3, gap=0.05):
    out, t = [], 0.0
    for text in words:
        out.append({"text": text, "start": t, "end": t + dur})
        t += dur + gap
    return out


class _Fake:
    """A throwaway executable `crisp-embed` whose behaviour is the given Python body
    (reads stdin, writes stdout). Installed into CRISP_EMBED for the test's duration."""

    def __init__(self, body):
        fd, self.path = tempfile.mkstemp(suffix=".py", prefix="fake_embed_")
        os.write(fd, ("#!/usr/bin/env python3\n" + textwrap.dedent(body)).encode())
        os.close(fd)
        os.chmod(self.path, os.stat(self.path).st_mode | stat.S_IEXEC | stat.S_IXGRP)
        self._prev = os.environ.get("CRISP_EMBED")
        os.environ["CRISP_EMBED"] = self.path

    def restore(self):
        if self._prev is None:
            os.environ.pop("CRISP_EMBED", None)
        else:
            os.environ["CRISP_EMBED"] = self._prev
        try:
            os.unlink(self.path)
        except OSError:
            pass


# A well-behaved helper: one similarity (1.0) per input pair.
_GOOD = """
    import json, sys
    pairs = json.load(sys.stdin)["pairs"]
    print(json.dumps({"similarities": [1.0 for _ in pairs]}))
"""


class MakeJudgeTests(unittest.TestCase):
    def tearDown(self):
        if getattr(self, "fake", None):
            self.fake.restore()

    def _install(self, body):
        self.fake = _Fake(body)

    def test_unset_env_disables_gate(self):
        prev = os.environ.pop("CRISP_EMBED", None)
        try:
            self.assertIsNone(semantic.make_judge())
        finally:
            if prev is not None:
                os.environ["CRISP_EMBED"] = prev

    def test_missing_binary_disables_gate(self):
        os.environ["CRISP_EMBED"] = "/no/such/crisp-embed"
        try:
            self.assertIsNone(semantic.make_judge())
        finally:
            os.environ.pop("CRISP_EMBED", None)

    def test_good_helper_yields_working_judge(self):
        self._install(_GOOD)
        judge = semantic.make_judge()
        self.assertIsNotNone(judge)
        self.assertAlmostEqual(judge("hello there", "hello again"), 1.0)

    def test_probe_failure_disables_gate(self):
        self._install("import sys; sys.exit(2)")
        self.assertIsNone(semantic.make_judge())

    def test_per_call_error_returns_none_not_raise(self):
        # Succeeds on the probe (identical strings) but errors otherwise — the judge
        # must swallow that and return None for the candidate, never raise.
        self._install("""
            import json, sys
            pairs = json.load(sys.stdin)["pairs"]
            a, b = pairs[0]
            if a != b:
                sys.exit(3)
            print(json.dumps({"similarities": [1.0]}))
        """)
        judge = semantic.make_judge()
        self.assertIsNotNone(judge)                 # probe passed
        self.assertIsNone(judge("different", "phrases"))


class RunValidationTests(unittest.TestCase):
    """`_run` must reject malformed helper output by raising (so make_judge falls back)."""

    def tearDown(self):
        self.fake.restore()

    def _run_one(self, body):
        self.fake = _Fake(body)
        return semantic._run(self.fake.path, [["a", "b"]])

    def test_nonzero_exit_raises(self):
        with self.assertRaises(RuntimeError):
            self._run_one("import sys; sys.exit(5)")

    def test_garbage_stdout_raises(self):
        with self.assertRaises(Exception):
            self._run_one("print('not json at all')")

    def test_count_mismatch_raises(self):
        with self.assertRaises(RuntimeError):
            self._run_one('print(\'{"similarities": []}\')')

    def test_nan_similarity_raises(self):
        with self.assertRaises(RuntimeError):
            self._run_one('print(\'{"similarities": [NaN]}\')')

    def test_string_similarity_raises(self):
        with self.assertRaises(RuntimeError):
            self._run_one('print(\'{"similarities": ["high"]}\')')

    def test_bool_similarity_raises(self):
        with self.assertRaises(RuntimeError):
            self._run_one('print(\'{"similarities": [true]}\')')

    def test_timeout_raises(self):
        self.fake = _Fake("import time; time.sleep(5)")
        with self.assertRaises(Exception):
            semantic._run(self.fake.path, [["a", "b"]], timeout=1)


class JudgePathIntegrationTests(unittest.TestCase):
    """detect_retakes driven through a REAL make_judge subprocess (what the pipeline
    does), not the in-process fake — so the production path itself is covered."""

    def tearDown(self):
        self.fake.restore()

    def test_detect_retakes_with_real_judge_subprocess(self):
        self.fake = _Fake(_GOOD)                     # judge always returns 1.0
        judge = semantic.make_judge()
        self.assertIsNotNone(judge)
        # Short pause-less repeat (run 3): below the run floor, but the (stubbed) strong
        # semantic score rescues it — exercising the judge branch end to end.
        words = seq(["the", "api", "is", "slow", "the", "api", "is", "fast"])
        spans = detect_retakes(words, min_run=3, require_pause=False, min_run_no_pause=9,
                               sem_min=0.7, silences=[], judge=judge)
        self.assertEqual(len(spans), 1)


if __name__ == "__main__":
    unittest.main()
