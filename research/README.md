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
Put clips and their labels side by side under `data/`:

```
data/clip01.wav            # 16 kHz mono
data/clip01.fillers.json   # {"fillers": [[1.20, 1.46], [8.03, 8.31]]}
```

Extract mono 16 kHz audio from any recording with:
```sh
ffmpeg -i input.mp4 -vn -ac 1 -ar 16000 -c:a pcm_s16le data/clip01.wav
```

The easiest source is your own recordings. A quick bootstrap: run Crisp's normal
clean, note where it cut "um/uh", and hand-correct those intervals into the JSON.
Keep a held-out set under `data/val/` for honest evaluation.

### 2. Train
```sh
python -m filler_classifier.train --data data/ --epochs 30
```

### 3. Evaluate (on held-out clips)
```sh
python -m filler_classifier.evaluate --data data/val --checkpoint checkpoints/filler_cnn.pt
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
