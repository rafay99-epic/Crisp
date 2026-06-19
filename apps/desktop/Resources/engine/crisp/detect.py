"""Detection: long pauses from real audio energy, and filler words from speech.

This is the analysis half of the engine — what to consider cutting. The cutting
itself lives in `edit`.
"""

import json
import re
import subprocess
from pathlib import Path

from .errors import CleanError
from .tools import ffmpeg_bin

# whisper.cpp's `--dtw` (token-level DTW timestamps) only accepts these built-in
# alignment-head presets. We infer the right one from the model's filename so the
# Swift side doesn't have to know about it. Anything not in this set (e.g. a
# CrisperWhisper build) simply runs without DTW.
DTW_ALIASES = frozenset({
    "tiny", "tiny.en", "base", "base.en", "small", "small.en",
    "medium", "medium.en", "large.v1", "large.v2", "large.v3", "large.v3.turbo",
})


def dtw_alias_for_model(model) -> str | None:
    """Map a whisper.cpp model file to its `--dtw` preset, or None if unknown.

    e.g. ``ggml-base.en.bin`` → ``base.en`` and
    ``ggml-large-v3-turbo-q5_0.bin`` → ``large.v3.turbo``.
    """
    stem = Path(model).name
    if stem.startswith("ggml-"):
        stem = stem[len("ggml-"):]
    if stem.endswith(".bin"):
        stem = stem[:-len(".bin")]
    stem = re.sub(r"-q\d+(_\d+)?$", "", stem)   # drop quantization suffix (-q5_0, -q8_0…)
    alias = stem.replace("-", ".")
    return alias if alias in DTW_ALIASES else None


# A word span shorter than this is treated as collapsed: whisper's heuristic
# segment end can fall at/before the DTW onset, which would drop the cut entirely
# (the renderer discards sub-10ms removals). Such a word is extended to the next
# word's onset — its true end slot.
MIN_WORD_SPAN = 0.02


def parse_transcription(data: dict) -> list:
    """Turn whisper.cpp `-oj`/`-ojf` JSON into word spans (seconds).

    With `-ml 1 -sow` each transcription entry is ~one word. When DTW token
    timestamps are present (`-ojf -dtw …`), the first token's ``t_dtw`` (in
    centiseconds) gives a far more accurate word *onset* than whisper's heuristic
    segment offset — so we trim the start to it. The end is the segment offset,
    except that DTW onsets can land at/past that end (collapsing the span); in
    that case the word is extended to the next word's onset so the cut isn't lost.
    Falls back cleanly to plain segment offsets when no DTW data is present.
    """
    raw = []
    for seg in data.get("transcription", []):
        text = seg.get("text", "")
        if not text.strip():
            continue
        offsets = seg.get("offsets", {})
        try:
            seg_from = float(offsets["from"]) / 1000.0
            seg_to = float(offsets["to"]) / 1000.0
        except (KeyError, TypeError, ValueError):
            continue
        start = seg_from
        for tok in seg.get("tokens", []):
            t_dtw = tok.get("t_dtw", -1)
            # Bind the onset to the first token that has real text and a computed
            # DTW time — never a leading blank/special token.
            if isinstance(t_dtw, (int, float)) and t_dtw >= 0 and tok.get("text", "").strip():
                start = t_dtw / 100.0       # centiseconds → seconds
                break
        raw.append({"text": text, "start": start, "seg_to": seg_to})

    words = []
    for i, w in enumerate(raw):
        end = w["seg_to"]
        if end - w["start"] < MIN_WORD_SPAN:        # collapsed by the DTW onset
            nxt = raw[i + 1]["start"] if i + 1 < len(raw) else None
            end = nxt if (nxt is not None and nxt > w["start"]) else w["start"]
        words.append({"text": w["text"], "start": w["start"], "end": end})
    return words


def extract_audio(src: Path, wav_path: Path, on_log) -> None:
    on_log("Extracting audio for analysis...")
    res = subprocess.run(
        [ffmpeg_bin(), "-y", "-i", str(src),
         "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(wav_path)],
        capture_output=True, text=True,
    )
    if res.returncode != 0 or not wav_path.exists():
        raise CleanError(f"Could not extract audio.\n{res.stderr[-800:]}")


def detect_silences(wav_path: Path, noise_db: float, min_pause: float, on_log) -> list:
    on_log("Detecting pauses / silence...")
    res = subprocess.run(
        [ffmpeg_bin(), "-i", str(wav_path),
         "-af", f"silencedetect=noise={noise_db}dB:d={min_pause}",
         "-f", "null", "-"],
        capture_output=True, text=True,
    )
    silences, start = [], None
    for line in res.stderr.splitlines():
        line = line.strip()
        if "silence_start:" in line:
            try:
                start = float(line.split("silence_start:")[1].strip().split()[0])
            except (IndexError, ValueError):
                start = None
        elif "silence_end:" in line and start is not None:
            try:
                end = float(line.split("silence_end:")[1].strip().split()[0])
                silences.append((start, end))
            except (IndexError, ValueError):
                pass
            start = None
    return silences


def whisper_command(whisper_bin, model, wav_path, out_prefix) -> list:
    """Build the whisper.cpp argv. `-ml 1 -sow` gives one word per segment; when
    the model has a known DTW preset we add `-dtw <alias> -ojf -nfa` for accurate
    per-word onsets (DTW is disabled under flash attention, so it must be off).
    Otherwise we keep the faster flash-attention path and plain `-oj` offsets.
    """
    cmd = [whisper_bin, "-m", str(model), "-f", str(wav_path),
           "-ml", "1", "-sow", "-of", str(out_prefix), "-pp"]
    alias = dtw_alias_for_model(model)
    if alias:
        cmd += ["-ojf", "-nfa", "-dtw", alias]
    else:
        cmd += ["-oj"]
    return cmd


def transcribe(whisper_bin, model, wav_path, out_prefix, on_log, on_progress):
    on_log("Transcribing (finding filler words)... this is the slow step.")
    json_path = Path(str(out_prefix) + ".json")
    proc = subprocess.Popen(
        whisper_command(whisper_bin, model, wav_path, out_prefix),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    for line in proc.stderr:
        if "progress =" in line:
            try:
                pct = int(line.split("progress =")[1].strip().split("%")[0])
                on_progress(pct / 100.0, f"Transcribing… {pct}%")
            except (IndexError, ValueError):
                pass
    proc.wait()
    if not json_path.exists():
        raise CleanError("Transcription failed — the speech model may be missing.")
    with open(json_path) as f:
        data = json.load(f)
    return parse_transcription(data)
