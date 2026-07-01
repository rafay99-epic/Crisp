"""Shared constants for the filler-classifier experiment.

Kept in one place so feature extraction, training, inference, and the Core ML
export all agree on the audio framing. These mirror the engine's analysis audio:
16 kHz mono (see packages/engine/crisp/detect.py:extract_audio).
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

# Fixed log-mel normalization, computed once over the PodcastFillers train split.
# FIXED constants — not per-clip or per-recording stats — so training chunks and
# full-recording inference are normalized identically (no train/serve skew), and
# the Swift inference helper just bakes in these two numbers. Recompute if the mel
# framing above changes (see the stats snippet in the README).
MEL_MEAN = -18.5658
MEL_STD = 17.9252

# Inference defaults (tunable; the shipped Core ML path mirrors these).
DEFAULT_THRESHOLD = 0.5      # P(filler) above this = filler chunk
MERGE_GAP_SEC = 0.12         # bridge filler runs separated by <= this
MIN_FILLER_SEC = 0.08        # drop predicted fillers shorter than this

# ---------------------------------------------------------------- Wren v2 (context)
# v2 is a fully-convolutional temporal model: it reads a log-mel SEQUENCE and emits a
# per-frame P(removable filler). Same mel framing/normalization as above (so train and
# inference agree), but instead of one 0.25s chunk it sees a multi-second window for
# context — the thing v0.0.8 lacked. Because it's fully convolutional, we train on
# fixed windows but run inference over a whole recording in one pass.
WINDOW_SEC = 4.0                                       # context window fed during training
WINDOW_FRAMES = round(WINDOW_SEC / FRAME_SEC)          # 400 mel frames (10 ms each)
NEG_PER_POS = 3                                        # negative windows per positive
HARD_NEG_FRAC = 0.5                                    # of negatives, share centered on a
                                                       # NATURAL/boundary filler (hard negatives)
