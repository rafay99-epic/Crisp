"""whisper.cpp invocation + JSON parsing — the filler-timestamp half of detect.

Pure logic only: the command builder and the JSON→words parser are tested with
captured fixtures, never by spawning whisper.
"""

import unittest

from crisp.detect import dtw_alias_for_model, parse_transcription, whisper_command


class DTWAliasTests(unittest.TestCase):
    def test_known_models_map_to_presets(self):
        self.assertEqual(dtw_alias_for_model("ggml-base.en.bin"), "base.en")
        self.assertEqual(dtw_alias_for_model("ggml-small.en.bin"), "small.en")
        self.assertEqual(dtw_alias_for_model("ggml-large-v3.bin"), "large.v3")
        self.assertEqual(dtw_alias_for_model("ggml-tiny.bin"), "tiny")

    def test_turbo_and_quantized_suffixes(self):
        # Quantization suffixes must be stripped; hyphens become dots.
        self.assertEqual(dtw_alias_for_model("ggml-large-v3-turbo.bin"), "large.v3.turbo")
        self.assertEqual(dtw_alias_for_model("ggml-large-v3-turbo-q5_0.bin"), "large.v3.turbo")
        self.assertEqual(dtw_alias_for_model("ggml-large-v3-turbo-q8_0.bin"), "large.v3.turbo")

    def test_full_path_is_accepted(self):
        self.assertEqual(
            dtw_alias_for_model("/Users/x/.crisp/models/ggml-base.en.bin"), "base.en")

    def test_unknown_models_return_none(self):
        # Anything without a built-in DTW preset (e.g. a CrisperWhisper build)
        # must fall back to no-DTW rather than passing a bad alias to whisper.
        self.assertIsNone(dtw_alias_for_model("ggml-crisper-whisper.bin"))
        self.assertIsNone(dtw_alias_for_model("some-random-model.bin"))


class WhisperCommandTests(unittest.TestCase):
    def test_known_model_uses_dtw_full_json_no_flash(self):
        cmd = whisper_command("whisper-cli", "ggml-base.en.bin", "a.wav", "/tmp/out")
        self.assertIn("-dtw", cmd)
        self.assertEqual(cmd[cmd.index("-dtw") + 1], "base.en")
        self.assertIn("-ojf", cmd)   # token-level JSON
        self.assertIn("-nfa", cmd)   # DTW is disabled under flash attention
        self.assertNotIn("-oj", cmd)
        self.assertIn("-ml", cmd)
        self.assertEqual(cmd[cmd.index("-ml") + 1], "1")

    def test_unknown_model_keeps_fast_segment_path(self):
        cmd = whisper_command("whisper-cli", "ggml-crisper.bin", "a.wav", "/tmp/out")
        self.assertNotIn("-dtw", cmd)
        self.assertNotIn("-nfa", cmd)
        self.assertNotIn("-ojf", cmd)
        self.assertIn("-oj", cmd)


# A trimmed slice of real `-ojf -dtw base.en` output (t_dtw in centiseconds).
DTW_JSON = {
    "transcription": [
        {"text": " Um,", "offsets": {"from": 0, "to": 520},
         "tokens": [{"text": " Um", "t_dtw": 18}, {"text": ",", "t_dtw": 34}]},
        {"text": " so", "offsets": {"from": 520, "to": 780},
         "tokens": [{"text": " so", "t_dtw": 58}]},
        {"text": " this", "offsets": {"from": 780, "to": 1310},
         "tokens": [{"text": " this", "t_dtw": 106}]},
    ]
}

# Plain `-oj` output (no tokens, segment offsets only) — the fallback path.
SEGMENT_JSON = {
    "transcription": [
        {"text": " Um,", "offsets": {"from": 100, "to": 600}},
        {"text": " hello", "offsets": {"from": 600, "to": 1200}},
    ]
}


class ParseTranscriptionTests(unittest.TestCase):
    def test_dtw_onset_overrides_segment_start(self):
        words = parse_transcription(DTW_JSON)
        self.assertEqual([w["text"] for w in words], [" Um,", " so", " this"])
        # Start trimmed to the first token's t_dtw (centiseconds → seconds)…
        self.assertAlmostEqual(words[0]["start"], 0.18)
        self.assertAlmostEqual(words[1]["start"], 0.58)
        # …end stays the segment offset.
        self.assertAlmostEqual(words[0]["end"], 0.52)

    def test_falls_back_to_segment_offsets_without_tokens(self):
        words = parse_transcription(SEGMENT_JSON)
        self.assertAlmostEqual(words[0]["start"], 0.10)
        self.assertAlmostEqual(words[0]["end"], 0.60)
        self.assertAlmostEqual(words[1]["start"], 0.60)

    def test_negative_t_dtw_is_ignored(self):
        # -1 means "not computed"; such tokens must not override the start.
        data = {"transcription": [
            {"text": " ok", "offsets": {"from": 300, "to": 900},
             "tokens": [{"text": " ok", "t_dtw": -1}]}]}
        words = parse_transcription(data)
        self.assertAlmostEqual(words[0]["start"], 0.30)

    def test_blank_and_malformed_segments_are_skipped(self):
        data = {"transcription": [
            {"text": "   ", "offsets": {"from": 0, "to": 100}},        # blank
            {"text": " word"},                                          # no offsets
            {"text": " ok", "offsets": {"from": 100, "to": 200}},       # good
        ]}
        words = parse_transcription(data)
        self.assertEqual([w["text"] for w in words], [" ok"])

    def test_collapsed_span_extends_to_next_word_onset(self):
        # A DTW onset that lands at/past whisper's segment end would collapse the
        # span to zero (and the renderer drops sub-10ms cuts). The word must extend
        # to the next word's onset instead — this is the Turbo regression.
        data = {"transcription": [
            {"text": " uh,", "offsets": {"from": 600, "to": 650},
             "tokens": [{"text": " uh", "t_dtw": 68}]},   # onset 0.68 > seg end 0.65
            {"text": " then", "offsets": {"from": 700, "to": 900},
             "tokens": [{"text": " then", "t_dtw": 72}]}]}  # onset 0.72
        words = parse_transcription(data)
        self.assertAlmostEqual(words[0]["start"], 0.68)
        self.assertAlmostEqual(words[0]["end"], 0.72)      # extended to next onset
        self.assertGreater(words[0]["end"] - words[0]["start"], 0)

    def test_collapsed_last_word_has_no_next_onset(self):
        # A collapsed final word (no next onset) stays zero-width — acceptable, and
        # the renderer will simply drop a sub-10ms cut.
        data = {"transcription": [
            {"text": " uh,", "offsets": {"from": 600, "to": 600},
             "tokens": [{"text": " uh", "t_dtw": 68}]}]}
        words = parse_transcription(data)
        self.assertAlmostEqual(words[0]["start"], 0.68)
        self.assertAlmostEqual(words[0]["end"], 0.68)

    def test_normal_span_keeps_segment_end(self):
        # A healthy span (DTW onset well before the segment end) is untouched.
        data = {"transcription": [
            {"text": " um,", "offsets": {"from": 100, "to": 600},
             "tokens": [{"text": " um", "t_dtw": 18}]},
            {"text": " ok", "offsets": {"from": 700, "to": 900}}]}
        words = parse_transcription(data)
        self.assertAlmostEqual(words[0]["start"], 0.18)
        self.assertAlmostEqual(words[0]["end"], 0.60)      # keeps segment end, not next onset

    def test_end_never_precedes_start(self):
        data = {"transcription": [
            {"text": " x", "offsets": {"from": 500, "to": 400},
             "tokens": [{"text": " x", "t_dtw": 480}]}]}
        words = parse_transcription(data)
        self.assertGreaterEqual(words[0]["end"], words[0]["start"])

    def test_leading_blank_token_does_not_set_onset(self):
        # A leading blank/special token carrying a t_dtw must be skipped for the
        # first real-text token's onset.
        data = {"transcription": [
            {"text": " hi", "offsets": {"from": 0, "to": 500},
             "tokens": [{"text": "", "t_dtw": 5}, {"text": " hi", "t_dtw": 30}]}]}
        words = parse_transcription(data)
        self.assertAlmostEqual(words[0]["start"], 0.30)

    def test_empty_input(self):
        self.assertEqual(parse_transcription({}), [])
        self.assertEqual(parse_transcription({"transcription": []}), [])


if __name__ == "__main__":
    unittest.main()
