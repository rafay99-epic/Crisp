"""Locating and probing the external tools the engine drives."""

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from .errors import CleanError


def _resolve_tool(env_var: str, candidates: tuple, hint: str) -> str:
    """Locate an external tool. The Swift app passes absolute paths to the
    binaries it bundles via env vars (CRISP_FFMPEG / CRISP_FFPROBE / CRISP_WHISPER);
    falling back to PATH keeps the plain `python3 clean_video.py …` CLI and a
    developer's Homebrew install working unchanged."""
    override = os.environ.get(env_var)
    if override and Path(override).exists():
        return override
    for name in candidates:
        path = shutil.which(name)
        if path:
            return path
    raise CleanError(f"{candidates[0]} not found. {hint}")


def ffmpeg_bin() -> str:
    return _resolve_tool("CRISP_FFMPEG", ("ffmpeg",), "Install it with:  brew install ffmpeg")


def ffprobe_bin() -> str:
    return _resolve_tool("CRISP_FFPROBE", ("ffprobe",), "Install it with:  brew install ffmpeg")


_HW_ENCODER_CACHE = None


def available_hw_encoders() -> set:
    """The hardware video encoders this ffmpeg build exposes — the `*_videotoolbox`
    (macOS) / `*_nvenc` / `*_qsv` / `*_amf` (Windows) names, parsed from
    `ffmpeg -encoders`. Cached (one subprocess per run); empty set if ffmpeg is
    missing or the probe fails, so the caller cleanly falls back to software."""
    global _HW_ENCODER_CACHE
    if _HW_ENCODER_CACHE is None:
        try:
            res = subprocess.run([ffmpeg_bin(), "-hide_banner", "-encoders"],
                                 capture_output=True, text=True, timeout=15)
            _HW_ENCODER_CACHE = set(re.findall(
                r"\b([a-z0-9]+_(?:videotoolbox|nvenc|qsv|amf))\b", res.stdout))
        except Exception:
            _HW_ENCODER_CACHE = set()
    return _HW_ENCODER_CACHE


def which_whisper():
    return _resolve_tool("CRISP_WHISPER", ("whisper-cli", "whisper-cpp", "main"),
                         "Install it with:  brew install whisper-cpp")


def which_filler():
    """The bundled Core ML filler-classifier helper (an opt-in alternative to
    whisper for filler detection). Resolved from CRISP_FILLER (set by the app to
    the bundled binary), falling back to PATH for a dev build."""
    return _resolve_tool("CRISP_FILLER", ("crisp-filler",),
                         "The filler-classifier helper ships with the Crisp app.")


def probe_video_fps(path: Path, logger=None):
    """The first video stream's base (``r_frame_rate``) and average
    (``avg_frame_rate``) rates, as raw ffprobe fraction strings (``"30000/1001"``).
    Returns ``("", "")`` when there's no video stream or the probe fails — the
    caller (crisp.framerate) treats unknown rates as "don't normalize", so a probe
    failure degrades to the source's own timing rather than breaking the clean.

    `logger` is optional (a no-op when None), mirroring `ffprobe_duration` — the
    rest of this module logs only through a passed-in logger."""
    res = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate,avg_frame_rate",
         "-of", "default=noprint_wrappers=1", str(path)],
        capture_output=True, text=True,
    )
    # Fail open: on a nonzero exit return ("", "") so a partial/garbled stdout can't
    # feed bad metadata into resolve_target_fps (which would then normalize on the
    # very path that's supposed to leave the source untouched).
    if res.returncode != 0:
        if logger is not None:
            logger.error(f"ffprobe couldn't read frame rate of {path} (exit {res.returncode})\n"
                         f"{(res.stderr or '').strip()[-800:]}")
        return "", ""
    r = avg = ""
    for line in res.stdout.splitlines():
        s = line.strip()
        if s.startswith("r_frame_rate="):
            r = s.split("=", 1)[1].strip()
        elif s.startswith("avg_frame_rate="):
            avg = s.split("=", 1)[1].strip()
    return r, avg


def parse_stream_meta(returncode: int, stdout: str, require_fps: bool = True) -> dict | None:
    """Pure parse of `ffprobe … -show_entries stream … -of json` into the metadata the
    FCPXML handoff needs, or None on failure: a bad exit, non-object/malformed output, no
    video stream, or (when `require_fps`) an unreadable frame rate. The frame rate is
    required for the probe that feeds the TIMELINE (the editor copy), because a wrong fps
    is silently catastrophic — every cut would land at the wrong source time. The SOURCE
    probe only needs pixel format + color (to drive the re-encode), so it passes
    `require_fps=False` and isn't rejected just because the source's r_frame_rate is
    missing/0 (it'll be normalized to a constant rate anyway). Less-critical missing fields
    (width/height/audio) always default. Pure (no subprocess) so it's unit-testable."""
    if returncode != 0:
        return None
    try:
        payload = json.loads(stdout)
    except (ValueError, TypeError):
        return None
    # Valid JSON that isn't the expected object/array shape (e.g. `null`, `5`, `[…]`)
    # must fail cleanly, not crash on `.get` / iteration.
    if not isinstance(payload, dict):
        return None
    streams = payload.get("streams", [])
    if not isinstance(streams, list):
        return None

    # audio_channels defaults to 0 so a source with no audio stream is distinguishable
    # from one with audio (the FCPXML builder declares audio only when channels > 0).
    # pix_fmt + color_* drive bit-depth-preserving re-encodes and the FCPXML colorSpace
    # (empty = unknown → caller keeps its safe default).
    meta = {"width": 1920, "height": 1080, "fps_num": 30, "fps_den": 1,
            "audio_rate": 48000, "audio_channels": 0,
            "pix_fmt": "", "color_primaries": "", "color_transfer": "", "color_space": "",
            "color_range": ""}

    def _int(value, default):
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    have_video = have_audio = fps_read = False
    for s in streams:
        if not isinstance(s, dict):
            continue
        kind = s.get("codec_type")
        if kind == "video" and not have_video:
            have_video = True
            meta["width"] = _int(s.get("width"), meta["width"])
            meta["height"] = _int(s.get("height"), meta["height"])
            for key in ("pix_fmt", "color_primaries", "color_transfer", "color_space",
                        "color_range"):
                v = s.get(key)
                if isinstance(v, str):
                    meta[key] = v
            rate = s.get("r_frame_rate", "")
            if isinstance(rate, str) and "/" in rate:
                n, d = rate.split("/", 1)
                n, d = _int(n, 0), _int(d, 0)
                if n > 0 and d > 0:
                    meta["fps_num"], meta["fps_den"], fps_read = n, d, True
        elif kind == "audio" and not have_audio:
            have_audio = True
            meta["audio_rate"] = _int(s.get("sample_rate"), meta["audio_rate"])
            # An audio stream EXISTS — if its channel count is missing/unparseable,
            # default to 2 (stereo), not 0. 0 is reserved for "no audio stream at all";
            # dropping audio just because channels didn't parse would be wrong.
            meta["audio_channels"] = _int(s.get("channels"), 2)
    # No video stream → can't build a video timeline. And for the timeline probe, a
    # missing/zero r_frame_rate would default to 30fps and misplace every cut (catastrophic),
    # so fps is required there; the source probe (require_fps=False) tolerates it.
    if not have_video:
        return None
    if require_fps and not fps_read:
        return None
    return meta


def probe_stream_meta(path: Path, logger=None, require_fps: bool = True) -> dict | None:
    """Stream metadata the FCPXML editor handoff needs (size, fps, audio, pixfmt, color),
    or None on a probe failure — see `parse_stream_meta`. Pass `require_fps=False` for the
    SOURCE probe (pixfmt/color only); the timeline probe keeps the default (fps required).
    `logger` is optional (no-op when None), like the other probes here."""
    # JSON output so each stream is a real object — robust vs. parsing flat key=value
    # lines (where there's no reliable per-stream delimiter).
    res = subprocess.run(
        [ffprobe_bin(), "-v", "error",
         "-show_entries",
         "stream=codec_type,width,height,r_frame_rate,sample_rate,channels,"
         "pix_fmt,color_primaries,color_transfer,color_space,color_range",
         "-of", "json", str(path)],
        capture_output=True, text=True,
    )
    meta = parse_stream_meta(res.returncode, res.stdout, require_fps=require_fps)
    if meta is None and logger is not None:
        logger.error(f"ffprobe couldn't read usable stream metadata of {path} (exit {res.returncode})\n"
                     f"{(res.stderr or '').strip()[-800:]}")
    return meta


def _ratio(value):
    """ffprobe prints HDR chromaticity/luminance as rationals ("13250/50000"); turn one
    into a float, or None if it's missing/garbage. Tolerates a plain number too."""
    if value is None:
        return None
    try:
        text = str(value)
        if "/" in text:
            num, den = text.split("/", 1)
            den = float(den)
            return float(num) / den if den else None
        return float(text)
    except (ValueError, TypeError):
        return None


def parse_hdr10_metadata(returncode: int, stdout: str) -> dict | None:
    """Pure parse of `ffprobe … -show_frames` JSON into HDR10 static metadata — the
    mastering-display color volume (primaries/white-point/luminance, in PHYSICAL units:
    chromaticity 0–1, luminance cd/m²) and the content light level (MaxCLL/MaxFALL) — read
    from the first frame's side-data. Returns `{"mastering_display": {...} | None,
    "content_light": {...} | None}`, or None when neither is present / the probe failed.
    Encoder-unit conversion + formatting lives in `encode.hdr_x265_params` (this stays a
    pure read of what the source declares). No subprocess, so it's unit-testable."""
    if returncode != 0:
        return None
    try:
        payload = json.loads(stdout)
    except (ValueError, TypeError):
        return None
    if not isinstance(payload, dict):
        return None
    frames = payload.get("frames", [])
    if not isinstance(frames, list):
        return None

    mastering = content_light = None
    for frame in frames:
        if not isinstance(frame, dict):
            continue
        for sd in frame.get("side_data_list", []) or []:
            if not isinstance(sd, dict):
                continue
            kind = sd.get("side_data_type")
            if kind == "Mastering display metadata" and mastering is None:
                mastering = _parse_mastering_display(sd)
            elif kind == "Content light level metadata" and content_light is None:
                content_light = _parse_content_light(sd)
    if not mastering and not content_light:
        return None
    return {"mastering_display": mastering, "content_light": content_light}


def _parse_mastering_display(sd: dict) -> dict | None:
    """Read every mastering-display field as a physical value; ALL-or-nothing (returns None
    if any field is missing/unparseable) so a partial probe can never yield a malformed
    x265 `master-display=` string."""
    keys = ("red_x", "red_y", "green_x", "green_y", "blue_x", "blue_y",
            "white_point_x", "white_point_y", "min_luminance", "max_luminance")
    out = {}
    for key in keys:
        v = _ratio(sd.get(key))
        if v is None:
            return None
        out[key] = v
    return out


def _parse_content_light(sd: dict) -> dict | None:
    """Read MaxCLL/MaxFALL (cd/m², integers); None if either is missing/unparseable."""
    try:
        return {"max_cll": int(sd["max_content"]), "max_fall": int(sd["max_average"])}
    except (KeyError, TypeError, ValueError):
        return None


def probe_hdr10_metadata(path: Path, logger=None) -> dict | None:
    """Probe the source's first frame for HDR10 static metadata (see `parse_hdr10_metadata`).
    Best-effort: a miss just means there's nothing to carry, so failures return None rather
    than raise (an HDR clean must never fail over optional metadata). `-read_intervals %+#1`
    reads only the first frame, so this is one cheap probe (the caller gates it to PQ/HLG)."""
    res = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-select_streams", "v:0",
         "-read_intervals", "%+#1", "-show_frames", "-of", "json", str(path)],
        capture_output=True, text=True,
    )
    meta = parse_hdr10_metadata(res.returncode, res.stdout)
    if meta is None and logger is not None:
        logger.debug(f"no HDR10 static metadata in {path} (exit {res.returncode})")
    return meta


def ffprobe_duration(path: Path, logger=None) -> float:
    out = subprocess.run(
        [ffprobe_bin(), "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(out.stdout.strip())
    except ValueError:
        # The caller turns 0.0 into a generic "couldn't read duration" error; log
        # the real ffprobe stderr here so the cause isn't lost.
        if logger is not None:
            logger.error(f"ffprobe couldn't read duration of {path} (exit {out.returncode})\n"
                         f"{(out.stderr or '').strip()[-800:]}")
        return 0.0
