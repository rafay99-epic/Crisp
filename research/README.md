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
python -m filler_classifier.train --dataset podcastfillers --data data/PodcastFillers --epochs 30
```
Each epoch prints validation Precision / Recall / F1 so you can watch it learn;
the best-F1 checkpoint is saved to `checkpoints/filler_cnn.pt`.

### 3. Evaluate (on the held-out test split)
```sh
python -m filler_classifier.evaluate --dataset podcastfillers --data data/PodcastFillers --split test
```

### 4. Try it on a clip
```sh
python -m filler_classifier.infer some_clip.wav
```

### 5. Export for the app
```sh
python -m filler_classifier.export_coreml
```

`infer.py` is the **reference implementation** — the shipped Core ML backend must
produce the same intervals from the same audio. Feature extraction (mel + chunking)
stays in the host, so the model itself is a pure `chunk → P(filler)` function,
trivial to verify against this script.
