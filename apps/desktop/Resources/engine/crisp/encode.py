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


def is_deep_pix_fmt(pix_fmt: str) -> bool:
    """True only for >8-bit pixel formats (real bit depth) — planar/semi-planar YUV
    (10/12/14/16-bit) and packed high-bit-depth RGB (rgb48 / rgba64 / 10-bit packed).
    Deliberately does NOT count wide chroma (4:2:2/4:4:4 can still be 8-bit), so callers
    that care specifically about bit depth (e.g. the Force-10-bit decision) don't mistake
    an 8-bit 4:2:2 source for a 10-bit one. `is_high_bit_depth` adds wide chroma on top."""
    pf = (pix_fmt or "").lower()
    deep = (pf.endswith(("10le", "10be", "12le", "12be", "14le", "14be", "16le", "16be"))
            or pf.startswith(("p010", "p012", "p016", "p210", "p216", "p410", "p416")))
    # Packed 16-bit RGB(A): rgb48/bgr48 (3×16) and rgba64/bgra64/argb64 (4×16); plus the
    # 10-bit packed RGB variants (x2rgb10, x2bgr10, gbrp already handled by the depth suffix).
    rgb_deep = any(tag in pf for tag in ("rgb48", "bgr48", "rgba64", "bgra64", "argb64",
                                         "abgr64", "rgb30", "x2rgb10", "x2bgr10"))
    return deep or rgb_deep


def is_high_bit_depth(pix_fmt: str) -> bool:
    """True for >8-bit OR non-4:2:0 pixel formats worth preserving on the editor copy
    instead of crushing to 8-bit yuv420p — real high bit depth (see `is_deep_pix_fmt`)
    plus 4:2:2 / 4:4:4 chroma. Used to decide what to PRESERVE; for the bit-depth-only
    question (is this actually 10-bit?), use `is_deep_pix_fmt`."""
    pf = (pix_fmt or "").lower()
    wide_chroma = "422" in pf or "444" in pf
    return is_deep_pix_fmt(pf) or wide_chroma


# The 10-bit 4:2:0 software pixel format every encoder we drive understands
# (libx264 High 10, libx265 Main10, libvpx-vp9 profile 2). It's the target when an
# 8-bit source is forced to 10-bit and isn't a wider-chroma format (those keep their
# chroma via WIDE_8_TO_10_PIX_FMT). We never synthesize wider chroma than the source had.
TEN_BIT_PIX_FMT = "yuv420p10le"

# Force-10-bit on an 8-bit WIDE-chroma source: bump to the matching 10-bit format so the
# chroma the source carried isn't thrown away on the way to 10-bit (libx264/libx265 both
# encode these). Anything else 8-bit falls through to TEN_BIT_PIX_FMT (10-bit 4:2:0).
WIDE_8_TO_10_PIX_FMT = {"yuv422p": "yuv422p10le", "yuv444p": "yuv444p10le"}


def resolve_pix_fmt(color_depth: str, src_pix_fmt: str):
    """Pick the output pixel format for the rendered clean from the color-depth mode
    and the source's own format, returning `(pix_fmt, notes)` — `notes` is a list of
    human-readable strings so any depth change is surfaced, never silent.

      "auto" — match the source: a high-bit-depth / wide-chroma source is preserved
               exactly (10-bit stays 10-bit, 4:2:2 stays 4:2:2); a plain 8-bit 4:2:0
               source stays 8-bit. The default — footage is never downgraded.
      "8"    — force 8-bit 4:2:0 (`yuv420p`). Notes the loss when the source was deeper.
      "10"   — force a 10-bit encode. A source that's already ≥10-bit is preserved as-is;
               an 8-bit source is upconverted to 10-bit (keeping its chroma — no real
               quality gain, the UI warns first — but it honors a 10-bit delivery spec).

    Whether the result needs the software encoder is the caller's call via
    `is_high_bit_depth(pix_fmt)` (Apple VideoToolbox is unreliable for >8-bit / wide
    chroma — the same lesson as the editor copy), so this stays a pure format decision."""
    src = (src_pix_fmt or "").strip()
    src_high = is_high_bit_depth(src) and bool(src)   # deep OR wide chroma — what to preserve
    src_deep = is_deep_pix_fmt(src) and bool(src)     # actually ≥10-bit — what "10" already satisfies
    notes = []

    if color_depth == "8":
        if src_high:
            notes.append("Downscaling to 8-bit 4:2:0 — your setting forces it (the source is higher quality).")
        return "yuv420p", notes

    if color_depth == "10":
        if src_deep:
            # Already ≥10-bit: preserve the source format exactly (keeps its chroma too)
            # rather than coercing it down to plain 4:2:0 10-bit.
            return src, notes
        # An 8-bit source (incl. 8-bit 4:2:2/4:4:4, which is_high_bit_depth flags as
        # wide-chroma but is NOT 10-bit) is upconverted — keeping its chroma where we can.
        notes.append("Encoding 8-bit source as 10-bit — your setting forces it (no quality gain).")
        return WIDE_8_TO_10_PIX_FMT.get(src.lower(), TEN_BIT_PIX_FMT), notes

    # "auto" (and any unexpected value): match the source. Preserve a high-bit-depth /
    # wide-chroma source; an empty/unknown or plain 8-bit format stays the safe 8-bit 4:2:0.
    if src_high:
        notes.append(f"Preserving the source's color depth ({src}).")
        return src, notes
    return "yuv420p", notes


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
