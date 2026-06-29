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
    deep = (pf.endswith(("9le", "9be", "10le", "10be", "12le", "12be", "14le", "14be", "16le", "16be"))
            or pf.startswith(("p010", "p012", "p016", "p210", "p216", "p410", "p416")))
    # Packed 16-bit RGB(A): rgb48/bgr48 (3×16) and rgba64/bgra64/argb64 (4×16); plus the
    # 10-bit packed RGB variants (x2rgb10, x2bgr10, gbrp already handled by the depth suffix).
    rgb_deep = any(tag in pf for tag in ("rgb48", "bgr48", "rgba64", "bgra64", "argb64",
                                         "abgr64", "rgb30", "x2rgb10", "x2bgr10"))
    return deep or rgb_deep


# Wide-chroma (4:2:2 / 4:4:4) formats whose ffmpeg names DON'T contain "444"/"422" — the
# semi-planar nv* variants and planar GBR (full-chroma) — so a substring check misses them.
_WIDE_444_ALIASES = ("gbrp", "gbrap", "nv24", "nv42")
_WIDE_422_ALIASES = ("nv16", "nv61")


def is_high_bit_depth(pix_fmt: str) -> bool:
    """True for >8-bit OR non-4:2:0 pixel formats worth preserving on the editor copy
    instead of crushing to 8-bit yuv420p — real high bit depth (see `is_deep_pix_fmt`)
    plus 4:2:2 / 4:4:4 chroma, INCLUDING the alias names that lack the digits (nv16/nv24/
    gbrp…). Used to decide what to PRESERVE; for the bit-depth-only question (is this
    actually 10-bit?), use `is_deep_pix_fmt`."""
    pf = (pix_fmt or "").lower()
    wide_chroma = ("422" in pf or "444" in pf
                   or pf in _WIDE_422_ALIASES or pf in _WIDE_444_ALIASES)
    return is_deep_pix_fmt(pf) or wide_chroma


# The 10-bit 4:2:0 software pixel format libx264/libx265 understand — the floor when an
# 8-bit source is upconverted and nothing wider is preserved.
TEN_BIT_PIX_FMT = "yuv420p10le"

# Max bit depth each SOFTWARE encoder we drive accepts (high bit depth always goes software).
# Verified against the bundled ffmpeg: libx265 reaches 12-bit, libx264 tops out at 10-bit,
# and this libvpx-vp9 build has no high-bit-depth at all (8-bit only). A source deeper than
# its encoder allows is capped here, so the render never hands the encoder a depth it rejects
# (which would otherwise fail and fall back to 8-bit). Default 12 for any unlisted codec.
_MAX_SOFTWARE_DEPTH = {"h264": 10, "hevc": 12, "vp9": 8}

# Display names for the codec keys, for user-facing notes ("H.264 can't keep…").
_CODEC_LABELS = {"h264": "H.264", "hevc": "HEVC", "vp9": "VP9"}


def _codec_label(video_codec: str) -> str:
    return _CODEC_LABELS.get(video_codec, video_codec.upper())


def _chroma_class(pix_fmt: str) -> str:
    """A source's chroma sampling as "444", "422", or "420" — covering the alias names that
    lack the digits (nv24/gbrp → 444, nv16 → 422), the semi-planar p###  family (its 2nd
    digit is the chroma: p2## = 4:2:2, p4## = 4:4:4, p0## = 4:2:0), and RGB (treated as
    full-chroma 4:4:4)."""
    pf = (pix_fmt or "").lower()
    if ("444" in pf or pf in _WIDE_444_ALIASES or pf.startswith("p4")
            or "rgb" in pf or "bgr" in pf or pf.startswith("gbr")):
        return "444"
    if "422" in pf or pf in _WIDE_422_ALIASES or pf.startswith("p2"):
        return "422"
    return "420"


def _bit_depth(pix_fmt: str) -> int:
    """A source's bit depth as 8, 10, or 12 — clamped to 12 (the deepest any encoder we drive
    reaches), so a 14/16-bit source lands at 12 rather than crushing to 8, and a 9-bit source
    maps UP to 10 (no encoder has a 9-bit mode, and 10-bit is lossless for it). Covers the
    semi-planar p0xx prefixes and packed high-bit-depth RGB."""
    pf = (pix_fmt or "").lower()
    if (pf.endswith(("12le", "12be", "14le", "14be", "16le", "16be"))
            or pf.startswith(("p012", "p016", "p216", "p416"))
            or any(t in pf for t in ("rgb48", "bgr48", "rgba64", "bgra64", "argb64", "abgr64"))):
        return 12
    if (pf.endswith(("9le", "9be", "10le", "10be")) or pf.startswith(("p010", "p210", "p410"))
            or any(t in pf for t in ("x2rgb10", "x2bgr10", "rgb30"))):
        return 10
    return 8


def _encodable_pix_fmt(pix_fmt: str, min_depth: int = 0, max_depth: int = 12) -> str:
    """A PLANAR YUV pixel format the chosen encoder accepts, keeping the source's chroma
    sampling and a bit depth in [`min_depth`, `max_depth`] (the source's own depth when those
    don't bind) — mapping semi-planar / packed / RGB sources (nv16, p010, yuyv422, rgb48,
    gbrp…) onto the `yuv###p[##le]` the encoder actually accepts, instead of handing it a raw
    format it'd reject (then fall back to 8-bit 4:2:0 on — the very chroma loss we're avoiding).
    `max_depth` is the encoder's ceiling (see `_MAX_SOFTWARE_DEPTH`), so e.g. a 12-bit source
    exported as H.264 (10-bit max) lands at 10-bit, not a failed 12-bit attempt."""
    depth = min(max(_bit_depth(pix_fmt), min_depth), max_depth)
    return f"yuv{_chroma_class(pix_fmt)}p" + ("" if depth <= 8 else f"{depth}le")


def resolve_pix_fmt(color_depth: str, src_pix_fmt: str, video_codec: str = "hevc"):
    """Pick the output pixel format for the rendered clean from the color-depth mode, the
    source's own format, and the CHOSEN encoder, returning `(pix_fmt, notes)` — `notes` is a
    list of human-readable strings so any depth change is surfaced, never silent. The result
    is always a format `video_codec`'s software encoder accepts (see `_encodable_pix_fmt` +
    `_MAX_SOFTWARE_DEPTH`) that keeps the source's chroma + bit depth where the encoder can;
    an exotic source layout, or a depth past the encoder's ceiling, is normalized rather than
    passed through raw (which would fail the encode and drop to 8-bit).

      "auto" — match the source: a high-bit-depth / wide-chroma source keeps its depth and
               chroma (10-bit stays 10-bit, 4:2:2 stays 4:2:2); a plain 8-bit 4:2:0 source
               stays 8-bit. The default — footage is never downgraded beyond the encoder limit.
      "8"    — force 8-bit 4:2:0 (`yuv420p`). Notes the loss when the source was higher.
      "10"   — force a 10-bit encode. A source that's already ≥10-bit keeps its depth/chroma;
               an 8-bit source is upconverted to 10-bit (keeping its chroma — no real quality
               gain, the UI warns first — but it honors a 10-bit delivery spec).

    Whether the result needs the software encoder is the caller's call via
    `is_high_bit_depth(pix_fmt)` (Apple VideoToolbox is unreliable for >8-bit / wide
    chroma — the same lesson as the editor copy), so this stays a pure format decision."""
    src = (src_pix_fmt or "").strip()
    src_high = is_high_bit_depth(src) and bool(src)   # deep OR wide chroma — what to preserve
    src_deep = is_deep_pix_fmt(src) and bool(src)     # actually >8-bit — what "10" already satisfies
    max_depth = _MAX_SOFTWARE_DEPTH.get(video_codec, 12)
    notes = []

    if color_depth == "8":
        if src_high:
            notes.append("Downscaling to 8-bit 4:2:0 — your setting forces it (the source is higher quality).")
        return "yuv420p", notes

    if color_depth == "10":
        # Already >8-bit keeps its own depth+chroma; an 8-bit source is upconverted to (at
        # least) 10-bit, keeping its chroma — unless the encoder's ceiling is lower (e.g. VP9
        # here is 8-bit, H.264 is 10-bit), in which case it lands lower and we say so.
        target = _encodable_pix_fmt(src, min_depth=10, max_depth=max_depth)
        tgt_depth = _bit_depth(target)
        if tgt_depth < 10:
            notes.append(f"{_codec_label(video_codec)} can't encode 10-bit — using {tgt_depth}-bit instead.")
        elif not src_deep:
            notes.append("Encoding 8-bit source as 10-bit — your setting forces it (no quality gain).")
        elif _bit_depth(src) > tgt_depth:
            notes.append(f"Encoding {tgt_depth}-bit — {_codec_label(video_codec)} can't keep the "
                         f"source's {_bit_depth(src)}-bit depth.")
        return target, notes

    # "auto" (and any unexpected value): match the source. A high-bit-depth / wide-chroma
    # source keeps its depth + chroma (normalized to a format the encoder accepts); an
    # empty/unknown or plain 8-bit 4:2:0 source stays the safe 8-bit 4:2:0.
    if src_high:
        target = _encodable_pix_fmt(src, max_depth=max_depth)
        src_depth, tgt_depth = _bit_depth(src), _bit_depth(target)
        if src_depth > tgt_depth:
            # The encoder can't carry the source's full bit depth (a 12-bit source as H.264
            # → 10-bit, a 10-bit source as VP9 → 8-bit): say what we actually landed at.
            notes.append(f"Encoding {tgt_depth}-bit — {_codec_label(video_codec)} can't keep the "
                         f"source's {src_depth}-bit depth.")
        else:
            notes.append(f"Preserving the source's color depth ({target}).")
        return target, notes
    return "yuv420p", notes


def hdr_x265_params(hdr_meta) -> str | None:
    """Build the libx265 `-x265-params` value that carries HDR10 static metadata from the
    source — the mastering-display color volume and content light level — or None when the
    probed metadata (see `tools.parse_hdr10_metadata`) is absent. x265 wants chromaticity in
    units of 0.00002 and luminance in 0.0001 cd/m² (so the probed physical values are scaled
    by 50000 / 10000), in a fixed `master-display=G(…)B(…)R(…)WP(…)L(max,min):max-cll=…`
    shape. Because the parse is all-or-nothing, a non-None result here is always well-formed.

    libx265 only — it's the encoder we drive for 10-bit/HDR (Apple VideoToolbox can't take
    these params), so `video_args` applies it solely on the libx265 path."""
    if not hdr_meta:
        return None
    parts = []
    md = hdr_meta.get("mastering_display")
    if md:
        def chroma(key):     # 0–1 chromaticity → 0.00002 units
            return int(round(md[key] * 50000))

        def lum(key):        # cd/m² → 0.0001 cd/m² units
            return int(round(md[key] * 10000))

        parts.append(
            "master-display="
            f"G({chroma('green_x')},{chroma('green_y')})"
            f"B({chroma('blue_x')},{chroma('blue_y')})"
            f"R({chroma('red_x')},{chroma('red_y')})"
            f"WP({chroma('white_point_x')},{chroma('white_point_y')})"
            f"L({lum('max_luminance')},{lum('min_luminance')})")
    cll = hdr_meta.get("content_light")
    if cll:
        parts.append(f"max-cll={cll['max_cll']},{cll['max_fall']}")
    return ":".join(parts) if parts else None


def video_args(codec: str, hardware: bool, quality: str, pix_fmt: str = "yuv420p",
               hdr_params: str | None = None) -> list:
    """ffmpeg `-c:v …` arguments for the chosen video encoder + quality level. `pix_fmt`
    defaults to 8-bit 4:2:0 (`yuv420p`, the compatible output for the rendered clean); the
    editor copy passes the source's own format to avoid a silent bit-depth/chroma downgrade.
    `hdr_params` (from `hdr_x265_params`) carries HDR10 static metadata — written explicitly
    only on the libx265 path AND only when the pixel format is actually ≥10-bit. We don't add
    it on an 8-bit fallback (no point), but we don't strip it either: ffmpeg auto-propagates
    the source's mastering metadata, and since the engine never tone-maps, an 8-bit encode of
    an HDR source is still PQ/BT.2020, so keeping that signaling is correct (see body)."""
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
    args = ["-c:v", encoder, "-preset", "veryfast", "-crf", str(crf)] + hevc_tag + ["-pix_fmt", pix_fmt]
    # HDR10 static metadata rides on libx265 only (the 10-bit/HDR path), and we only WRITE it
    # explicitly on a deep output — there's no point adding it to an 8-bit fallback (the ladder
    # can drop a failed 10-bit encode to yuv420p with the same codec). Note we don't try to
    # STRIP it on 8-bit: ffmpeg auto-propagates the source's mastering metadata, and since the
    # engine never tone-maps, an 8-bit encode of an HDR source is still PQ/BT.2020 — keeping the
    # HDR signaling is correct (stripping it would make players read PQ pixels as SDR).
    if hdr_params and encoder == "libx265" and is_deep_pix_fmt(pix_fmt):
        args += ["-x265-params", hdr_params]
    return args


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
