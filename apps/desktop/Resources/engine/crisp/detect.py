"""Detection: long pauses from real audio energy, and filler words from speech.

This is the analysis half of the engine — what to consider cutting. The cutting
itself lives in `edit`.
"""

import json
import subprocess
from pathlib import Path

from .errors import CleanError
from .tools import ffmpeg_bin


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


def transcribe(whisper_bin, model, wav_path, out_prefix, on_log, on_progress):
    on_log("Transcribing (finding filler words)... this is the slow step.")
    json_path = Path(str(out_prefix) + ".json")
    proc = subprocess.Popen(
        [whisper_bin, "-m", str(model), "-f", str(wav_path),
         "-ml", "1", "-sow", "-oj", "-of", str(out_prefix), "-pp"],
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
    words = []
    for seg in data.get("transcription", []):
        o = seg.get("offsets", {})
        try:
            start, end = float(o["from"]) / 1000.0, float(o["to"]) / 1000.0
        except (KeyError, TypeError, ValueError):
            continue
        if seg.get("text", "").strip():
            words.append({"text": seg["text"], "start": start, "end": end})
    return words
