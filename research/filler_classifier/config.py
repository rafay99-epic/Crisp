"""Shared constants for the filler-classifier experiment.

Kept in one place so feature extraction, training, inference, and the Core ML
export all agree on the audio framing. These mirror the engine's analysis audio:
16 kHz mono (see apps/desktop/Resources/engine/crisp/detect.py:extract_audio).
"""

SAMPLE_RATE = 16000          # Hz — matches the engine's extracted analysis WAV
N_FFT = 400                  # 25 ms STFT window
HOP_LENGTH = 160             # 10 ms hop → one mel frame per 10 ms
N_MELS = 64                  # mel bands per frame

FRAME_SEC = HOP_LENGTH / SAMPLE_RATE                 # 0.010 s per mel frame
CHUNK_SEC = 0.25                                     # classifier sees 250 ms of audio
CHUNK_HOP_SEC = 0.10                                 # one decision every 100 ms

CHUNK_FRAMES = round(CHUNK_SEC / FRAME_SEC)          # 25 mel frames per chunk
CHUNK_HOP_FRAMES = round(CHUNK_HOP_SEC / FRAME_SEC)  # 10 frames between chunks

# Inference defaults (tunable; the shipped Core ML path mirrors these).
DEFAULT_THRESHOLD = 0.5      # P(filler) above this = filler chunk
MERGE_GAP_SEC = 0.12         # bridge filler runs separated by <= this
MIN_FILLER_SEC = 0.08        # drop predicted fillers shorter than this
