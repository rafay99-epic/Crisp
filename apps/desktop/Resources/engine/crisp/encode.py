"""Builds the ffmpeg video/audio encoder arguments for the final render.

Cuts are always re-encoded (frame-accurate trims need it), so this is where the
quality/codec choices land. Software encoders (libx264/libx265/libvpx-vp9) use
CRF; the Apple hardware encoders (VideoToolbox) use a constant-quality `-q:v`. A
named quality level maps to the right number per codec so the UI never exposes
raw scales. Not every codec fits every container (VP9 is WebM-only; the mp4
family can't hold it), so `resolve_codecs` coerces the choice to the container.
"""

from pathlib import Path

# Quality level → CRF for software encoders (lower = better). Each codec's CRF
# scale is its own — x264/x265 are 0–51, VP9 is 0–63 — so the levels are tuned
# per codec rather than shared.
SOFTWARE_CRF = {
    "h264": {"maximum": 16, "high": 20, "balanced": 23, "smaller": 28},
    "hevc": {"maximum": 18, "high": 23, "balanced": 26, "smaller": 30},
    "vp9": {"maximum": 20, "high": 28, "balanced": 34, "smaller": 40},
}
# Quality level → VideoToolbox -q:v (higher = better).
HARDWARE_QV = {"maximum": 80, "high": 65, "balanced": 55, "smaller": 45}


def is_high_bit_depth(pix_fmt: str) -> bool:
    """True for >8-bit / non-4:2:0 pixel formats worth preserving on the editor copy
    instead of crushing to 8-bit yuv420p (10/12/16-bit, or 4:2:2 / 4:4:4 chroma)."""
    pf = (pix_fmt or "").lower()
    deep = pf.endswith(("10le", "10be", "12le", "12be", "16le", "16be")) \
        or pf.startswith(("p010", "p012", "p016", "p210", "p216", "p410", "p416"))
    wide_chroma = "422" in pf or "444" in pf
    return deep or wide_chroma


def video_args(codec: str, hardware: bool, quality: str, pix_fmt: str = "yuv420p") -> list:
    """ffmpeg `-c:v …` arguments for the chosen video encoder + quality level. `pix_fmt`
    defaults to 8-bit 4:2:0 (`yuv420p`, the compatible output for the rendered clean); the
    editor copy passes the source's own format to avoid a silent bit-depth/chroma downgrade."""
    quality = quality if quality in HARDWARE_QV else "high"
    pix_fmt = pix_fmt or "yuv420p"

    if codec == "vp9":
        # VP9 has no Apple hardware encoder, so it's always software. `-b:v 0`
        # switches libvpx-vp9 into constant-quality mode (CRF as the target, not a
        # cap); `-row-mt 1` + `-cpu-used` claw back some of VP9's slowness.
        crf = SOFTWARE_CRF["vp9"][quality]
        # `-tile-columns 2` is what lets `-row-mt 1` actually parallelize across
        # cores; without it VP9 (already the slow, software-only path) barely
        # threads. `-cpu-used 2` keeps a sane speed/quality operating point.
        return ["-c:v", "libvpx-vp9", "-crf", str(crf), "-b:v", "0",
                "-row-mt", "1", "-tile-columns", "2", "-deadline", "good",
                "-cpu-used", "2", "-pix_fmt", pix_fmt]

    codec = codec if codec in ("h264", "hevc") else "h264"
    hevc_tag = ["-tag:v", "hvc1"] if codec == "hevc" else []  # QuickTime-friendly HEVC

    if hardware:
        encoder = "hevc_videotoolbox" if codec == "hevc" else "h264_videotoolbox"
        return ["-c:v", encoder, "-q:v", str(HARDWARE_QV[quality])] + hevc_tag + ["-pix_fmt", pix_fmt]

    encoder = "libx265" if codec == "hevc" else "libx264"
    crf = SOFTWARE_CRF[codec][quality]
    return ["-c:v", encoder, "-preset", "veryfast", "-crf", str(crf)] + hevc_tag + ["-pix_fmt", pix_fmt]


def audio_args(codec: str, bitrate_kbps: int) -> list:
    """ffmpeg `-c:a …` arguments for the chosen audio encoder + bitrate."""
    encoder = "libopus" if codec == "opus" else "aac"
    return ["-c:a", encoder, "-b:a", f"{int(bitrate_kbps)}k"]


# Output containers Crisp can write. The mp4 family + mkv + ts take the H.264/HEVC
# + AAC/Opus stack; webm is its own world — only VP8/VP9/AV1 video + Vorbis/Opus
# audio — so choosing it switches codecs (see resolve_codecs). flv is excluded
# (no HEVC, AAC-only). "auto" (the default) matches the input container.
SUPPORTED_CONTAINERS = ("mp4", "mkv", "mov", "m4v", "ts", "webm")
_FASTSTART_CONTAINERS = {"mp4", "mov", "m4v"}  # moov-atom relocation is mp4-family only

# WebM only accepts these. Crisp writes VP9 + Opus into it (the universally
# supported pairing); VP8/AV1/Vorbis are valid in the format but not what we emit.
WEBM_VIDEO_CODEC = "vp9"
WEBM_AUDIO_CODEC = "opus"


def resolve_container(choice: str, src_suffix: str) -> str:
    """Pick the output container. An explicit choice wins (validated against the
    supported set); "auto" matches the input file's extension, falling back to mp4
    when that isn't a container we mux into (e.g. an .avi / .flv source)."""
    if choice and choice != "auto":
        return choice if choice in SUPPORTED_CONTAINERS else "mp4"
    ext = src_suffix.lower().lstrip(".")
    return ext if ext in SUPPORTED_CONTAINERS else "mp4"


def default_output_path(src, container: str, out_dir=None) -> Path:
    """Where the cleaned file lands when no explicit `--out` is given:
    `<name>_cleaned.<container>` inside `out_dir` if one is set, otherwise right
    beside the source. `container` is the already-resolved container, so it drives
    the extension (an "auto" .mkv source keeps .mkv, etc.)."""
    name = f"{Path(src).stem}_cleaned.{container}"
    return (Path(out_dir).expanduser() / name) if out_dir else Path(src).with_name(name)


def resolve_codecs(container: str, video_codec: str, audio_codec: str, hardware: bool):
    """Coerce the codec choices to ones the chosen container can actually hold,
    returning `(video_codec, audio_codec, hardware, notes)` — `notes` is a list of
    human-readable strings explaining any change, so the swap is never silent.

    WebM forces VP9 + Opus in software (no Apple hardware VP9 encoder); every other
    container we write can't hold VP9, so it's coerced back to H.264 there."""
    notes = []
    if container == "webm":
        if video_codec != WEBM_VIDEO_CODEC:
            notes.append(f"WebM uses VP9 video, not {video_codec.upper()}.")
            video_codec = WEBM_VIDEO_CODEC
        if audio_codec != WEBM_AUDIO_CODEC:
            notes.append(f"WebM uses Opus audio, not {audio_codec.upper()}.")
            audio_codec = WEBM_AUDIO_CODEC
        if hardware:
            notes.append("Encoding VP9 in software — there's no hardware VP9 encoder.")
            hardware = False
    elif video_codec == "vp9":
        notes.append(f"{container.upper()} can't hold VP9 — using H.264 video.")
        video_codec = "h264"
    return video_codec, audio_codec, hardware, notes


def container_args(container: str) -> list:
    """ffmpeg muxer flags specific to the chosen container — just the faststart
    moov relocation, which only does anything for the mp4 family."""
    return ["-movflags", "+faststart"] if container in _FASTSTART_CONTAINERS else []
