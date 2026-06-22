# research/ — model experiments for Crisp

Heavy, dependency-laden ML code that is **never shipped**. The desktop engine
(`apps/desktop/Resources/engine/`) stays stdlib-only; only an *exported model
artifact* (a Core ML `.mlpackage`) ever crosses into the app. This directory is
where those artifacts are trained.

## filler_classifier — model #1 (audio)

An **opt-in** alternative to whisper for the filler-detection step — it does not
replace whisper as the default. It's a small, fast, English-only classifier you
train on your own footage.

- **Input:** 16 kHz mono audio (exactly what the engine extracts for analysis,
  see `crisp/detect.py:extract_audio`).
- **Output:** filler time-ranges — the same shape `detect.py` already consumes.
- **What it learns:** filler-vs-speech only. Pauses/silence stay with ffmpeg
  `silencedetect`, so this model has one narrow, learnable job.

### Package layout (split by model generation)

The shared audio frontend + publishing live at the top; each model generation is its
own subpackage. Run modules with their version prefix
(`python -m filler_classifier.v2.train`); publishing is version-agnostic.

```
filler_classifier/
  config.py  features.py                          # SHARED — mel framing + log-mel transform
  publish_hf.py  promote_model.py  MODEL_CARD.md  # SHARED — Hugging Face publish / promote
  v1/   the original per-chunk classifier (chunk model, v0.0.x)
        model · corpora · dataset · labeling · train · infer
        export_coreml · evaluate · benchmark · validate · report
  v2/   the context-aware temporal model (sequence TCN — Wren v2)
        model · derive_labels · validate_labels · preprocess
        dataset · train · infer · export_coreml
```

The **v1** workflow is documented below. The **v2** workflow (derive labels → preprocess
→ train → infer → export) is in `NOTES.md` §6b.

### Setup
```sh
cd research
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### 1. Get labeled data
The model trains on one of three sources, selected with `--dataset`:

**a) PodcastFillers (default, recommended).** 35k human-labeled "uh"/"um" events
across 350+ speakers — diverse, so the model generalizes. Download from
<https://podcastfillers.github.io/> and extract to `data/PodcastFillers/`.
The loader reads `metadata/PodcastFillers.csv` (filler = `label_consolidated_vocab`
in {Uh, Um}; `event_*_inclip` columns place it inside each 1 s clip) and the clips
under `audio/clip_wav/<split>/`.

> ⚠️ The archive is Zip64 (>4 GB). macOS's built-in `unzip` corrupts the large
> entries ("bad zipfile offset") — the 1 s clips extract fine, but grab
> `metadata/PodcastFillers.csv` from the site's standalone download if it's missing.
> We only need `audio/clip_wav/` + that CSV; the full episode audio is unused.

**b) SEP-28k (Apple stuttering events).** Filler = the `Interjection` annotator
count. Labels are clip-level (coarser — no within-clip timing). The clone ships
only labels + scripts, so download audio first (`download_audio.py` then
`extract_clips.py` in `data/ml-stuttering-events-dataset/`), which writes clips to
`clips/<Show>/<EpId>/`.

**c) Your own recordings (`--dataset folder`).** For later domain-adaptation to
Crisp's talking-head footage. Put `*.wav` (16 kHz mono) + `*.fillers.json`
(`{"fillers": [[1.20, 1.46], …]}`) side by side under a folder. Extract audio with
`ffmpeg -i in.mp4 -vn -ac 1 -ar 16000 -c:a pcm_s16le data/clip01.wav`.

### 2. Train
```sh
# PodcastFillers, using its built-in train/validation splits:
python -m filler_classifier.v1.train --dataset podcastfillers --data data/PodcastFillers --epochs 30
```
Each epoch prints validation Precision / Recall / F1 so you can watch it learn;
the best-F1 checkpoint is saved to `checkpoints/filler_cnn.pt`.

### 3. Evaluate (on the held-out test split)
```sh
python -m filler_classifier.v1.evaluate --dataset podcastfillers --data data/PodcastFillers --split test
```

### 4. Try it on a clip
```sh
python -m filler_classifier.v1.infer some_clip.wav
```

### 5. Export for the app (Core ML)
coremltools' native blob writer has **no working build on bleeding-edge Python**
(3.14 here fails with `BlobWriter not loaded`), so the export runs in a separate
env on a supported Python (3.10–3.12). It needs only torch + coremltools — no
audio stack:
```sh
python3.10 -m venv .venv-export
./.venv-export/bin/pip install -r requirements-export.txt
./.venv-export/bin/python -m filler_classifier.v1.export_coreml   # → checkpoints/FillerClassifier.mlpackage
```
The exported model is a pure `chunk [1,1,n_mels,CHUNK_FRAMES] → P(filler)` function;
it matches the PyTorch model to ~1e-9 (parity-checked). Feature extraction (mel +
chunking) stays in the host, so `infer.py` is the **reference implementation** the
shipped backend must reproduce.

### 6. Validate on your OWN footage (precision + recall)
The test-split F1 is on podcasts; to judge the model on *your* domain you need
ground truth on your own video. `validate` makes that a ~10-minute job: label one
short window by ear, and it grades the model's predictions against your labels.

```sh
# 1) cut a window to label (writes window.wav + an empty labels.json):
python -m filler_classifier.v1.validate prepare /tmp/test.wav --start 60 --end 240

# 2) play window.wav; add every um/uh you hear as [start,end] (seconds) to labels.json:
#    {"fillers": [[12.3, 12.6], [45.1, 45.8]]}
#    Label by ear — recall depends on you catching what the model missed.

# 3) grade it:
python -m filler_classifier.v1.validate score window.wav --labels labels.json --threshold 0.7
```
It reports precision (were the cuts real fillers?), recall (did it catch the real
ones?), and lists the **false positives** (cut, but not a filler) and **misses** so
you can see exactly where it errs.

## Normalization constants
Log-mel is standardized with **fixed** constants (`config.MEL_MEAN`, `MEL_STD`),
not per-clip/per-recording stats — so training chunks and full-recording inference
are normalized identically (no train/serve skew), and the Swift helper just bakes
in the two numbers. **If you change the mel framing (`N_FFT`/`HOP_LENGTH`/`N_MELS`),
recompute them** over the train split:

```python
import csv, torch
from pathlib import Path
from filler_classifier import features
root = Path("data/PodcastFillers"); cd = root/"audio"/"clip_wav"
names = [(r["clip_split_subset"], r["clip_name"]) for r in
         csv.DictReader(open(root/"metadata"/"PodcastFillers.csv")) if r["clip_split_subset"] == "train"]
s = ss = n = 0
for split, name in names[::max(1, len(names)//4000)]:   # ~4k-clip sample = a stable estimate
    mel = features.log_mel(features.load_waveform(str(cd/split/name)))
    s += float(mel.sum()); ss += float((mel*mel).sum()); n += mel.numel()
mean = s / n
var = max(0.0, ss / n - mean * mean)                    # clamp: guard float round-off < 0
print("MEL_MEAN =", round(mean, 4), "MEL_STD =", round(var ** 0.5, 4))
```
Changing normalization means **retrain + re-export** (the old checkpoint expects the old inputs).

## Environment notes (bleeding-edge Python)
- **Audio loading:** torchaudio 2.8+ routes `load()` through TorchCodec, which has
  no wheel here — so WAVs are read with the stdlib `wave` module (`features.py`).
- **Core ML export:** runs in `.venv-export` on Python 3.10 (see step 5).
- **PodcastFillers zip** is Zip64; macOS `unzip` corrupts entries >4 GB ("bad
  zipfile offset"). The 1 s clips extract fine; if `metadata/PodcastFillers.csv`
  is missing, copy the standalone CSV from the dataset site.
