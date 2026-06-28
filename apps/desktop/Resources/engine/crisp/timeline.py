"""Editor handoff: build a non-destructive FCPXML timeline from Crisp's cut list.

This is the "export to editor" path (Model A): instead of rendering a new video,
Crisp hands a video editor a copy of the ORIGINAL footage plus a timeline that
references it with the kept in/out ranges. Zero re-encode, every cut still
adjustable in the editor. DaVinci Resolve — including the free edition — imports
FCPXML via File ▸ Import ▸ Timeline; the Studio-only scripting API is not required,
which is what makes this work for the ~99% of users on free Resolve.

Every time value is an exact integer-frame rational (`k*den/num` seconds), so each
edit lands precisely on a frame boundary. A non-frame-aligned time is the single
most common cause of FCPXML import rejection ("the item is not on an edit frame
boundary"), so the whole module works in integer frames and only converts to the
rational seconds strings FCPXML wants at the very end.

Pure string-building (no ffmpeg, no IO) so it's fully unit-testable; the media copy
and the ffprobe that supplies width/fps/audio live in the pipeline.
"""

import math
from pathlib import Path
from xml.sax.saxutils import escape

from .errors import CleanError

# FCPXML 1.9 imports cleanly across DaVinci Resolve 18–21. Newer versions (1.10+)
# and the `.fcpxmld` bundle form are flaky to import, so we deliberately target 1.9
# and always emit a single flat .fcpxml file.
FCPXML_VERSION = "1.9"


def secs_to_frames(sec: float, num: int, den: int) -> int:
    """Seconds → whole frame index at a `num/den` fps (e.g. 30000/1001)."""
    return int(round(sec * num / den))


def frame_time(frames: int, num: int, den: int) -> str:
    """`frames` at `num/den` fps as an exact, reduced FCPXML time string.

    A frame lasts `den/num` seconds, so `frames` frames = `frames*den/num` s. The
    fraction is reduced (and printed without a denominator when it's a whole number)
    to match what Final Cut writes."""
    n, d = frames * den, num
    g = math.gcd(n, d) or 1
    n, d = n // g, d // g
    return f"{n}s" if d == 1 else f"{n}/{d}s"


def timeline_seconds(keep: list, num: int, den: int) -> float:
    """The kept duration as it actually lands on the frame grid — the sum of each
    clip's whole-frame count × the frame duration. This matches what build_fcpxml()
    writes (which snaps every span to frames), so reported new/saved seconds agree
    with the real timeline instead of the raw second spans. Falls back to the raw
    sum when the frame rate is unknown."""
    if num <= 0 or den <= 0:
        return sum(max(0.0, e - s) for s, e in keep)
    total_frames = 0
    for s, e in keep:
        f = secs_to_frames(e, num, den) - secs_to_frames(s, num, den)
        if f > 0:
            total_frames += f
    return total_frames * den / num


# FCPXML audioRate is a fixed enumerated token set (per Apple's DTD), NOT a free
# integer — only these values are valid. Anything else (16k/22.05k/24k/…) must fall
# back to a valid token rather than emit a non-conformant rate that breaks import.
_AUDIO_RATE_TOKENS = {
    32000: "32k", 44100: "44.1k", 48000: "48k",
    88200: "88.2k", 96000: "96k", 176400: "176.4k", 192000: "192k",
}


def _audio_rate_attr(hz: int) -> str:
    """FCPXML audioRate token for a sample rate, defaulting to 48k for anything
    outside the enumerated set (a raw integer isn't a valid audioRate)."""
    return _AUDIO_RATE_TOKENS.get(int(hz), "48k")


def build_fcpxml(*, media_uri: str, name: str, num: int, den: int,
                 width: int, height: int, audio_rate: int, audio_channels: int,
                 duration: float, keep: list, has_audio: bool = True) -> str:
    """Return a flat FCPXML document (a string) describing the cut timeline.

    media_uri        — `file://` URI of the (copied) media the timeline references.
    name             — display name for the asset/project (already un-escaped text).
    num, den         — source frame rate as a fraction (e.g. 60/1, 30000/1001).
    width, height    — source resolution.
    audio_rate, audio_channels — source audio (Hz, channel count).
    duration         — full source duration in seconds (the asset length).
    keep             — list of (start_sec, end_sec) source spans to keep, in order.

    Raises CleanError if there's nothing to keep (never write an empty timeline).
    """
    if num <= 0 or den <= 0:
        raise CleanError("Can't build an editor timeline: unknown source frame rate.")

    frame_dur = frame_time(1, num, den)
    # Drop-frame applies only to the NTSC 29.97 / 59.94 rates — NOT to 23.976
    # (24000/1001), which is non-drop. A too-broad check mislabels 23.976 timelines.
    drop = "DF" if (den == 1001 and num in (30000, 60000)) else "NDF"
    # Attribute-safe escaping: saxutils.escape() leaves quotes intact, which would
    # break a name/URL placed inside a double-quoted XML attribute — escape them too.
    name_x = escape(name, {'"': "&quot;", "'": "&apos;"})
    uri_x = escape(media_uri, {'"': "&quot;", "'": "&apos;"})
    arate = _audio_rate_attr(audio_rate)
    # Audio is declared only when the source actually has it — a phantom hasAudio="1"
    # on a silent screen recording produces a wrong (and import-warning) timeline.
    has_audio = has_audio and audio_channels > 0
    chans = max(1, audio_channels)
    # Map channel count to an FCPXML audio layout (stereo is wrong for >2 channels).
    layout = "mono" if chans <= 1 else ("stereo" if chans == 2 else "surround")
    total_frames = max(1, secs_to_frames(duration, num, den))

    # Snap each kept span to whole frames and lay the segments back-to-back on the
    # timeline (each `offset` = the running total of kept frames so far). Clamp to the
    # asset's frame count so a span that rounds past the (possibly re-encoded) copy's
    # length can't land out of bounds → Resolve "media out of range".
    clips, timeline_frames = [], 0
    for i, (s, e) in enumerate(keep):
        sf = min(secs_to_frames(s, num, den), total_frames)
        ef = min(secs_to_frames(e, num, den), total_frames)
        dur_f = ef - sf
        if dur_f <= 0:                              # span collapsed to <1 frame — skip
            continue
        clips.append(
            f'          <asset-clip ref="a1" offset="{frame_time(timeline_frames, num, den)}" '
            f'name="{name_x} ({i + 1})" start="{frame_time(sf, num, den)}" '
            f'duration="{frame_time(dur_f, num, den)}" format="r1"/>')
        timeline_frames += dur_f

    if not clips:
        raise CleanError("Can't build an editor timeline: no segments survived to keep.")

    asset_audio = (f' hasAudio="1" audioSources="1" audioChannels="{chans}" audioRate="{arate}"'
                   if has_audio else ' hasAudio="0"')
    seq_audio = f' audioLayout="{layout}" audioRate="{arate}"' if has_audio else ""

    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="{FCPXML_VERSION}">
  <resources>
    <format id="r1" name="FFVideoFormat{height}p{int(round(num / den))}" frameDuration="{frame_dur}" width="{width}" height="{height}" colorSpace="1-1-1 (Rec. 709)"/>
    <asset id="a1" name="{name_x}" start="0s" duration="{frame_time(total_frames, num, den)}" hasVideo="1" videoSources="1"{asset_audio} format="r1">
      <media-rep kind="original-media" src="{uri_x}"/>
    </asset>
  </resources>
  <library>
    <event name="Crisp">
      <project name="{name_x} (Crisp cut)">
        <sequence format="r1" duration="{frame_time(timeline_frames, num, den)}" tcStart="0s" tcFormat="{drop}"{seq_audio}>
          <spine>
{chr(10).join(clips)}
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
'''


def project_paths(src: Path, out_dir=None):
    """Where the editor handoff lands: a `<stem> (Crisp)` project folder (in out_dir
    if given, else beside the source) holding the media copy + the .fcpxml. Returns
    (project_dir, media_copy_path, fcpxml_path)."""
    src = Path(src)
    parent = Path(out_dir).expanduser() if out_dir else src.parent
    project_dir = parent / f"{src.stem} (Crisp)"
    media_copy = project_dir / src.name
    fcpxml = project_dir / f"{src.stem}.fcpxml"
    return project_dir, media_copy, fcpxml
