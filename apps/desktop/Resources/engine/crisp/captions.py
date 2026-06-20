"""Subtitle/caption export (SRT + WebVTT) from the cleaned timeline.

The engine already transcribes speech with whisper.cpp to find filler words; this
re-times those word timestamps onto the *cleaned* (jump-cut) timeline and writes
sidecar `.srt`/`.vtt` files beside the cleaned video — so `clip_cleaned.mp4` ships
with `clip_cleaned.srt` ready to drop into YouTube / Premiere / Final Cut.

Pure stdlib, no I/O except the thin `write_captions` wrapper — everything else is
testable string/number math. Cue grouping follows broadcast/streaming norms
(Netflix/BBC): ≤42 chars/line, ≤2 lines, ≤17 chars/sec reading speed, 0.85–6 s per
cue, and a new cue forced at sentence ends and at pauses — segmentation Crisp gets
for free from its per-word timestamps.
"""

from pathlib import Path

from .text import is_filler

# Cue-shaping defaults (industry guidelines; see captions research). Cues are
# bounded to ≤2 lines of ≤42 chars and stretched to a readable minimum duration, so
# reading speed stays sane without forcing splits on a chars/second metric (which
# over-splits short cues whose span is briefly tiny).
MAX_CHARS_PER_LINE = 42
MAX_LINES = 2
MIN_CUE_DUR = 0.85        # seconds (≈ Netflix 5/6 s floor)
MAX_CUE_DUR = 6.0         # seconds (under Netflix 7 s ceiling)
CUE_SPLIT_GAP = 0.5       # a gap ≥ this between words forces a new cue
MIN_GAP = 0.08            # keep ~2 frames between adjacent cues


def original_to_cleaned(t, keep):
    """Map a time `t` on the original timeline to the cleaned (concatenated-keep)
    timeline. `keep` is the sorted, non-overlapping list of kept `(start, end)`
    segments the renderer concatenates. A `t` inside a removed gap clamps to the
    start of the next kept segment."""
    offset = 0.0
    for s, e in keep:
        if t < s:
            return offset
        if t <= e:
            return offset + (t - s)
        offset += e - s
    return offset


def retime_words(words, keep):
    """Re-time spoken words onto the cleaned timeline. Drops filler words (they were
    cut) and words that fall entirely inside a removed region; clamps a word that
    straddles a cut to the kept segment it overlaps. Returns a list of
    `{text, start, end}` on the cleaned timeline, in order."""
    out = []
    for w in words:
        text = (w.get("text") or "").strip()
        if not text or is_filler(w.get("text", "")):
            continue
        ws, we = float(w["start"]), float(w["end"])
        seg = next(((s, e) for s, e in keep if we > s and ws < e), None)
        if seg is None:
            continue   # word lives entirely in a removed gap
        s, e = seg
        cs = original_to_cleaned(max(ws, s), keep)
        ce = original_to_cleaned(min(we, e), keep)
        if ce <= cs:
            ce = cs + 0.04
        out.append({"text": text, "start": cs, "end": ce})
    return out


def _wrap_lines(text, max_chars=MAX_CHARS_PER_LINE):
    """Greedy word-wrap into lines of at most `max_chars` (never splits a word)."""
    lines, line = [], ""
    for word in text.split():
        if not line:
            line = word
        elif len(line) + 1 + len(word) <= max_chars:
            line += " " + word
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines or [text]


def _cue(words):
    text = " ".join(w["text"] for w in words)
    return {"start": words[0]["start"], "end": words[-1]["end"], "lines": _wrap_lines(text)}


def group_into_cues(words):
    """Pack re-timed words into subtitle cues: start a new cue at a sentence end, at
    a pause ≥ CUE_SPLIT_GAP, or when the running cue would exceed the line-count or
    duration limit. Then nudge too-short cues up to MIN_CUE_DUR."""
    cues, cur = [], []

    def would_overflow(nxt):
        text = " ".join(w["text"] for w in cur + [nxt])
        dur = nxt["end"] - cur[0]["start"]
        return len(_wrap_lines(text)) > MAX_LINES or dur > MAX_CUE_DUR

    for w in words:
        if cur:
            gap = w["start"] - cur[-1]["end"]
            ends_sentence = cur[-1]["text"].rstrip().endswith((".", "!", "?", "…"))
            if gap >= CUE_SPLIT_GAP or ends_sentence or would_overflow(w):
                cues.append(_cue(cur))
                cur = []
        cur.append(w)
    if cur:
        cues.append(_cue(cur))

    # Stretch a too-short cue toward the next one (keeping a small gap), so a quick
    # word still stays on screen long enough to read.
    for i, c in enumerate(cues):
        if c["end"] - c["start"] < MIN_CUE_DUR:
            ceiling = cues[i + 1]["start"] - MIN_GAP if i + 1 < len(cues) else c["start"] + MIN_CUE_DUR
            c["end"] = max(c["end"], min(c["start"] + MIN_CUE_DUR, max(ceiling, c["end"])))
    return cues


def _fmt(seconds, sep):
    seconds = max(0.0, seconds)
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"


def to_srt(cues):
    """SubRip: numbered cues, `HH:MM:SS,mmm` timestamps, CRLF, blank line per cue."""
    blocks = []
    for i, c in enumerate(cues, 1):
        body = [str(i), f"{_fmt(c['start'], ',')} --> {_fmt(c['end'], ',')}", *c["lines"], ""]
        blocks.append("\r\n".join(body))
    return "\r\n".join(blocks) + "\r\n" if blocks else ""


def _escape_vtt(line):
    return line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def to_vtt(cues):
    """WebVTT: `WEBVTT` header, `HH:MM:SS.mmm` timestamps, escaped cue text."""
    out = ["WEBVTT", ""]
    for c in cues:
        out.append(f"{_fmt(c['start'], '.')} --> {_fmt(c['end'], '.')}")
        out.extend(_escape_vtt(line) for line in c["lines"])
        out.append("")
    return "\n".join(out) + "\n"


def caption_paths(out_path):
    """`(srt_path, vtt_path)` beside the cleaned output (`clip_cleaned.mp4` →
    `clip_cleaned.srt` / `.vtt`). Pure — no I/O."""
    p = Path(out_path)
    return p.with_suffix(".srt"), p.with_suffix(".vtt")


def build_captions(words, keep):
    """Words (original timeline) + kept segments → subtitle cues (cleaned timeline)."""
    return group_into_cues(retime_words(words, keep))


def write_captions(out_path, words, keep, fmt):
    """Write the requested sidecar caption file(s). `fmt` is one of
    `srt`/`vtt`/`both`. Returns `(srt_path_str, vtt_path_str)` ("" when not written).
    UTF-8, no BOM. Best-effort — a caption write must never fail the clean."""
    if fmt == "none":
        return "", ""
    cues = build_captions(words, keep)
    if not cues:
        return "", ""
    srt_path, vtt_path = caption_paths(out_path)
    srt_out = vtt_out = ""
    try:
        if fmt in ("srt", "both"):
            srt_path.write_text(to_srt(cues), encoding="utf-8")
            srt_out = str(srt_path)
        if fmt in ("vtt", "both"):
            vtt_path.write_text(to_vtt(cues), encoding="utf-8")
            vtt_out = str(vtt_path)
    except OSError:
        pass
    return srt_out, vtt_out
