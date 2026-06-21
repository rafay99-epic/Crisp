"""Waveform → log-mel chunks.

The model classifies short fixed-length chunks of log-mel spectrogram. This is
the single source of truth for that transform: training and inference both go
through `chunks_from_waveform`, so the two can never drift apart.
"""
from __future__ import annotations

import wave

import numpy as np
import torch
import torchaudio
from torch.nn import functional as F

from . import config

_mel = torchaudio.transforms.MelSpectrogram(
    sample_rate=config.SAMPLE_RATE,
    n_fft=config.N_FFT,
    hop_length=config.HOP_LENGTH,
    n_mels=config.N_MELS,
)
_to_db = torchaudio.transforms.AmplitudeToDB(top_db=80.0)


# PCM sample widths → (numpy dtype, scale to [-1, 1]). Covers 8/16/32-bit PCM,
# which is everything ffmpeg's `-c:a pcm_s16le` and the corpus clips produce.
_PCM = {1: (np.uint8, 128.0), 2: (np.dtype("<i2"), 32768.0), 4: (np.dtype("<i4"), 2147483648.0)}


def load_waveform(path: str) -> torch.Tensor:
    """Load a WAV as a mono 16 kHz waveform of shape [samples].

    Uses the stdlib `wave` module rather than torchaudio.load: torchaudio 2.8+
    delegates decoding to TorchCodec, which has no wheel on bleeding-edge Python.
    Our clips (and Crisp's extracted analysis audio) are plain PCM WAV, so `wave`
    reads them with no extra dependency — the same stdlib-only stance as the engine.
    """
    with wave.open(str(path), "rb") as w:
        sr, channels, width, n = (w.getframerate(), w.getnchannels(),
                                  w.getsampwidth(), w.getnframes())
        raw = w.readframes(n)
    if width not in _PCM:
        raise ValueError(f"{path}: unsupported PCM sample width {width} bytes")

    dtype, scale = _PCM[width]
    data = np.frombuffer(raw, dtype=dtype).astype(np.float32)
    if width == 1:                                 # 8-bit PCM is unsigned, centered at 128
        data -= 128.0
    data /= scale
    if channels > 1:                               # downmix to mono
        data = data.reshape(-1, channels).mean(axis=1)

    wav = torch.from_numpy(data.copy())
    if sr != config.SAMPLE_RATE:                   # functional.resample is pure torch (no codec)
        wav = torchaudio.functional.resample(wav, sr, config.SAMPLE_RATE)
    return wav


def log_mel(waveform: torch.Tensor) -> torch.Tensor:
    """[samples] → log-mel spectrogram [n_mels, time]."""
    return _to_db(_mel(waveform))


def normalize(mel: torch.Tensor) -> torch.Tensor:
    """Standardize log-mel with FIXED dataset constants.

    Using fixed constants (not per-clip or per-recording mean/std) is what keeps
    training and full-recording inference seeing the same input distribution — and
    it's the normalization the Swift helper will replicate with two baked-in numbers.
    """
    return (mel - config.MEL_MEAN) / config.MEL_STD


def _chunk_starts(num_frames: int):
    """Yield each chunk's start frame for a spectrogram of num_frames frames."""
    f0 = 0
    while f0 + config.CHUNK_FRAMES <= num_frames:
        yield f0
        f0 += config.CHUNK_HOP_FRAMES


def chunks_from_waveform(waveform: torch.Tensor):
    """Return (patches, centers).

    patches: tensor [N, 1, n_mels, CHUNK_FRAMES]
    centers: list of chunk center times in seconds (one per patch)
    """
    mel = normalize(log_mel(waveform))            # [n_mels, T], fixed-constant norm

    patches, centers = [], []
    for f0 in _chunk_starts(mel.shape[1]):
        patches.append(mel[:, f0:f0 + config.CHUNK_FRAMES].unsqueeze(0))
        center_frame = f0 + config.CHUNK_FRAMES / 2.0
        centers.append(center_frame * config.FRAME_SEC)

    if not patches:
        empty = torch.empty(0, 1, config.N_MELS, config.CHUNK_FRAMES)
        return empty, []
    return torch.stack(patches), centers


def chunk_at(waveform: torch.Tensor, center_sec: float) -> torch.Tensor:
    """One normalized log-mel chunk [1, n_mels, CHUNK_FRAMES] centered at center_sec.

    Used for the short corpus clips (PodcastFillers, SEP-28k): we know where the
    filler sits, so we sample the single chunk over it instead of the whole clip.
    Normalization matches `chunks_from_waveform` (same fixed constants), so training
    chunks and sliding-inference chunks see the same statistics. Clips shorter
    than one chunk are right-padded.
    """
    mel = normalize(log_mel(waveform))                      # [n_mels, T]
    if mel.shape[1] < config.CHUNK_FRAMES:
        mel = F.pad(mel, (0, config.CHUNK_FRAMES - mel.shape[1]))

    center_frame = center_sec / config.FRAME_SEC
    f0 = int(round(center_frame - config.CHUNK_FRAMES / 2.0))
    f0 = max(0, min(f0, mel.shape[1] - config.CHUNK_FRAMES))
    return mel[:, f0:f0 + config.CHUNK_FRAMES].unsqueeze(0)
