"""Waveform → log-mel chunks.

The model classifies short fixed-length chunks of log-mel spectrogram. This is
the single source of truth for that transform: training and inference both go
through `chunks_from_waveform`, so the two can never drift apart.
"""
from __future__ import annotations

import torch
import torchaudio

from . import config

_mel = torchaudio.transforms.MelSpectrogram(
    sample_rate=config.SAMPLE_RATE,
    n_fft=config.N_FFT,
    hop_length=config.HOP_LENGTH,
    n_mels=config.N_MELS,
)
_to_db = torchaudio.transforms.AmplitudeToDB(top_db=80.0)


def load_waveform(path: str) -> torch.Tensor:
    """Load an audio file as a mono 16 kHz waveform of shape [samples]."""
    wav, sr = torchaudio.load(path)
    if wav.shape[0] > 1:                          # downmix to mono
        wav = wav.mean(dim=0, keepdim=True)
    if sr != config.SAMPLE_RATE:
        wav = torchaudio.functional.resample(wav, sr, config.SAMPLE_RATE)
    return wav.squeeze(0)


def log_mel(waveform: torch.Tensor) -> torch.Tensor:
    """[samples] → log-mel spectrogram [n_mels, time]."""
    return _to_db(_mel(waveform))


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
    mel = log_mel(waveform)                       # [n_mels, T]
    # per-utterance normalization keeps levels comparable across recordings
    mel = (mel - mel.mean()) / (mel.std() + 1e-5)

    patches, centers = [], []
    for f0 in _chunk_starts(mel.shape[1]):
        patches.append(mel[:, f0:f0 + config.CHUNK_FRAMES].unsqueeze(0))
        center_frame = f0 + config.CHUNK_FRAMES / 2.0
        centers.append(center_frame * config.FRAME_SEC)

    if not patches:
        empty = torch.empty(0, 1, config.N_MELS, config.CHUNK_FRAMES)
        return empty, []
    return torch.stack(patches), centers
