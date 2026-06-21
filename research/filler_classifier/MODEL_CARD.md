---
license: cc-by-4.0
tags:
  - audio-classification
  - filler-word-detection
  - core-ml
  - speech
language:
  - en
---

# Wren — Crisp filler detector

**Wren** is the fast, lightweight model in Crisp's filler-detection family (named
after birds — keen ears, clean song; the larger, higher-accuracy sibling is
**Kestrel**). A wren is the tiniest bird yet punches far above its size — fitting
for a ~75k-param CNN that hits 0.94 precision at ~600× real-time.

It detects **filler words** ("uh", "um") in speech for the
[Crisp](https://rafay99.com) macOS app — a fast, on-device alternative to running
full speech-to-text just to find fillers.

- **Input:** one log-mel chunk, `[1, 1, 64, 25]` (250 ms of 16 kHz mono audio,
  standardized with fixed constants `MEL_MEAN=-18.5658`, `MEL_STD=17.9252`).
- **Output:** `filler_prob` — P(this chunk is a filler), 0…1.
- **Format:** a single-file Core ML `.mlmodel` (download directly, no unzip).
  Runs on-device — Core ML schedules it across the Neural Engine, GPU, or CPU.

Feature extraction (mel + chunking + the slide/merge into time ranges) lives in
the host app; the model itself is a pure `chunk → probability` function.

## Training

- **Data:** [PodcastFillers](https://podcastfillers.github.io/) — ~35k human-labeled
  "uh"/"um" events, 350+ speakers. Trained on the `train` split.
- **Task:** binary filler-vs-speech on 250 ms chunks (silence/pauses are handled
  separately by the app via ffmpeg `silencedetect`).

## Evaluation (held-out, episode-disjoint `test` split)

| Threshold | Precision | Recall | F1 |
|-----------|-----------|--------|----|
| 0.5 | 0.914 | 0.933 | 0.924 |
| **0.7** | **0.944** | 0.894 | 0.918 |
| 0.8 | 0.959 | 0.863 | 0.908 |

Speed: ~600× real-time on CPU. Recommended operating threshold **0.7** (Crisp
favors precision — a false positive cuts real speech). Main error mode: occasional
confusion of short real words; breaths/laughter/music are rarely misfired.

## Limitations

English only. Trained on podcast audio; very different domains (heavy accents,
noisy rooms) may need a higher threshold or a fine-tune. Not a transcriber — it
only flags fillers.

## Files & versions (open weights)

Everything is downloadable — pick whichever you need:

| File | What |
|------|------|
| `Wren.mlmodel` | Core ML model (Apple Neural Engine). A single file the app downloads directly. |
| `Wren.pt` | Raw PyTorch weights (`state_dict`) — for your own inference/fine-tuning. |
| `Wren.config.json` | Audio framing + normalization + input/output names + recommended threshold. |

**Versioning:** the version is the repo's commit count, **`v0.0.N`** (mirrors
Crisp's `0.<commits>` scheme); each release is one commit + one tag. Pin an exact
version in the URL:

```
https://huggingface.co/rafay99-epic/crisp-models/resolve/v0.0.5/Wren.mlmodel
```

`main` always points at the latest.

## License

Code: GPL-3.0 (Crisp). Model weights derive from PodcastFillers (CC).
Credited to Syntax Lab Technology / Abdul Rafay.
