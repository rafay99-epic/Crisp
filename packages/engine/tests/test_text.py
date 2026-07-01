"""Filler-word matching — the call that decides what speech gets cut."""

import unittest

from crisp.text import is_filler, normalize_word


class NormalizeWordTests(unittest.TestCase):
    def test_strips_case_and_punctuation(self):
        self.assertEqual(normalize_word("  Um, "), "um")
        self.assertEqual(normalize_word("Uh?!"), "uh")
        self.assertEqual(normalize_word('"Hmm..."'), "hmm")
        self.assertEqual(normalize_word("Hmm…"), "hmm")  # trailing ellipsis char

    def test_blank_collapses_to_empty(self):
        self.assertEqual(normalize_word("   "), "")
        self.assertEqual(normalize_word("..."), "")


class IsFillerTests(unittest.TestCase):
    def test_explicit_vocabulary(self):
        for word in ["um", "uh", "uhm", "er", "erm", "hm", "hmm", "mm", "aww", "ahem"]:
            self.assertTrue(is_filler(word), f"{word!r} should be a filler")

    def test_case_and_punctuation_insensitive(self):
        self.assertTrue(is_filler("Um,"))
        self.assertTrue(is_filler("UH!"))
        self.assertTrue(is_filler("  Hmm... "))

    def test_elongated_and_variant_spellings(self):
        # The shape patterns catch the endless variants whisper emits.
        for word in ["ummm", "ummh", "uhhh", "errr", "hummm", "ahhh", "awww",
                     "mmm", "mhmm", "uh-huh", "mm-hmm"]:
            self.assertTrue(is_filler(word), f"{word!r} should match a filler pattern")

    def test_real_words_are_not_fillers(self):
        # Anchored matching must leave ordinary speech alone — including the
        # near-misses the shape patterns are carefully written to exclude.
        for word in ["human", "away", "him", "hum", "umbrella", "error",
                     "ahead", "awesome", "the", "hello", "mom"]:
            self.assertFalse(is_filler(word), f"{word!r} must NOT be a filler")

    def test_empty_is_not_a_filler(self):
        self.assertFalse(is_filler(""))
        self.assertFalse(is_filler("   "))


if __name__ == "__main__":
    unittest.main()
