"""Builds the ffmpeg video/audio encoder arguments for the final render.

Cuts are always re-encoded (frame-accurate trims need it), so this is where the
quality/codec choices land. Software encoders (libx264/libx265) use CRF; the Apple
hardware encoders (VideoToolbox) use a constant-quality `-q:v`. A named quality
level maps to the right number per codec so the UI never exposes raw scales.
"""

# Quality level → CRF for software encoders (lower = better).
SOFTWARE_CRF = {
    "h264": {"maximum": 16, "high": 20, "balanced": 23, "smaller": 28},
    "hevc": {"maximum": 18, "high": 23, "balanced": 26, "smaller": 30},
}
# Quality level → VideoToolbox -q:v (higher = better).
HARDWARE_QV = {"maximum": 80, "high": 65, "balanced": 55, "smaller": 45}


def video_args(codec: str, hardware: bool, quality: str) -> list:
    """ffmpeg `-c:v …` arguments for the chosen video encoder + quality level."""
    quality = quality if quality in HARDWARE_QV else "high"
    codec = codec if codec in ("h264", "hevc") else "h264"
    hevc_tag = ["-tag:v", "hvc1"] if codec == "hevc" else []  # QuickTime-friendly HEVC

    if hardware:
        encoder = "hevc_videotoolbox" if codec == "hevc" else "h264_videotoolbox"
        return ["-c:v", encoder, "-q:v", str(HARDWARE_QV[quality])] + hevc_tag + ["-pix_fmt", "yuv420p"]

    encoder = "libx265" if codec == "hevc" else "libx264"
    crf = SOFTWARE_CRF[codec][quality]
    return ["-c:v", encoder, "-preset", "veryfast", "-crf", str(crf)] + hevc_tag + ["-pix_fmt", "yuv420p"]


def audio_args(codec: str, bitrate_kbps: int) -> list:
    """ffmpeg `-c:a …` arguments for the chosen audio encoder + bitrate."""
    encoder = "libopus" if codec == "opus" else "aac"
    return ["-c:a", encoder, "-b:a", f"{int(bitrate_kbps)}k"]
