# Wren — on-device filler-word model: notes & journal

Working notes for the **Wren** filler-detection model and its integration into the
Crisp app. Kept as a running journal — for future work, and as raw material for a
blog post. Bullet-point heavy on purpose.

---

## 1. What Wren is

- A **tiny CNN audio classifier** (~75k params, **94 KB** on disk). Not an LLM, not whisper.
- Answers one yes/no question per ~0.25 s of audio: **"is this a filler (um/uh) or speech?"**
- Purpose in Crisp: a **fast, on-device alternative to whisper** for the *filler-detection* step (an opt-in, experimental backend). Pauses are still found by ffmpeg `silencedetect`; captions still need whisper.
- Wins: **~600× real-time**, 94 KB, no heavy transcription (quiet fans). English only.

---

## 2. The data

### PodcastFillers (primary — what Wren is trained on)
- Source: <https://podcastfillers.github.io/> (Adobe/Interspeech 2022). License: CC (audio from CC SoundCloud).
- ~**35k** human-labeled "uh"/"um" events + ~50k other sounds; **350+ speakers**, gender-balanced, 145 h.
- Local: `research/data/PodcastFillers/` (git-ignored). `audio/clip_wav/<split>/<clip>.wav` (1-s, 16 kHz mono) + `metadata/PodcastFillers.csv`.
- CSV columns we use: `clip_name`, `label_consolidated_vocab` (filler = `Uh`/`Um`), `event_start/end_inclip` (exact filler position in the 1-s clip), `clip_split_subset` (train/validation/test/extra).
- Gotchas:
  - `podcast_filename` contains commas → **must** parse with the `csv` module, not split-on-comma.
  - The download zip is **Zip64 (>4 GB)**; macOS `unzip` corrupts the big entries ("bad zipfile offset") — the 1-s clips extract fine; restore `metadata/PodcastFillers.csv` from the standalone download if missing.
  - Clips are nested by split: `clip_wav/<split>/<clip>.wav` (not flat).

### SEP-28k (Apple — optional, for later "more data" experiments)
- Repo: <https://github.com/apple/ml-stuttering-events-dataset> — cloned to `research/data/ml-stuttering-events-dataset/` (git-ignored).
- Ships **labels + scripts only, no audio**. License: **CC BY-NC** (non-commercial → experiments only, NOT the shipped model).
- Filler signal = the `Interjection` annotator count in `SEP-28k_labels.csv`. Coarser than PodcastFillers (clip-level, no within-clip timing).
- Audio downloaded via our `download_sep28k.py` (a macOS-friendly rewrite of Apple's `download_audio.py`, which assumes `wget` + old numpy):
  - `python3 download_sep28k.py` → `wavs/<Show>/<EpId>.wav` (16 kHz mono via curl + ffmpeg, skips dead URLs).
  - Status: ~240 episodes downloaded (many 2011–2012 URLs are dead → fewer than 385; normal).
  - Kaggle mirror exists (`ikrbasak/sep-28k`) if the script's URLs rot further.

---

## 3. How Wren was trained (`research/filler_classifier/`)

- **Task framing:** binary filler-vs-speech on 0.25 s log-mel "chunks" (silence handled elsewhere, so the model has one narrow job).
- **Features** (`features.py`, the single source of truth, shared by train + inference):
  - 16 kHz mono → torchaudio MelSpectrogram (n_fft=400, hop=160, **n_mels=64**) → dB → **fixed-constant normalization** (`MEL_MEAN=-18.5658`, `MEL_STD=17.9252`).
  - **Fixed** norm (not per-clip/per-recording) was a key fix — see issue log below.
  - A "chunk" = 25 mel frames (0.25 s); slide by 10 frames (0.1 s) at inference.
- **Model** (`model.py`): small 2-D CNN (Conv→BN→ReLU ×3 → global pool → 1 logit + sigmoid).
- **Train** (`train.py`): `--dataset podcastfillers` uses the corpus's built-in train/validation splits; BCEWithLogitsLoss with `pos_weight`; saves best-val-F1 checkpoint. Seeded.
- **Eval**: held-out, **episode-disjoint** test split → **F1 ≈ 0.928** (P=0.935, R=0.921). Not overfit (test ≈ val).
- **Benchmark** (`benchmark.py` / `report.py`): threshold sweep, false-positives-by-sound, per-filler recall, speed. FillerBench (`research/FillerBench/`, `swift run FillerBench`) is the native dashboard over `report.py`.
- **Commands:**
  ```sh
  cd research && source .venv/bin/activate
  python -m filler_classifier.train --dataset podcastfillers --data data/PodcastFillers --epochs 30
  python -m filler_classifier.evaluate --dataset podcastfillers --data data/PodcastFillers --split test
  python -m filler_classifier.infer some.wav --threshold 0.7        # reference impl
  ```

### Export + hosting
- Export to a **single-file Core ML `.mlmodel`** (neuralnetwork) in a **Python 3.10** env (`.venv-export`; coremltools' BlobWriter has no Py3.14 build).
  ```sh
  ./.venv-export/bin/python -m filler_classifier.export_coreml   # → checkpoints/Wren.mlmodel
  ```
- Published to **Hugging Face**: <https://huggingface.co/rafay99-epic/crisp-models> (`publish_hf.py`).
  - **Versioning = repo commit count** → `v0.0.N` tags. Pin: `.../resolve/v0.0.6/Wren.mlmodel`.
  - Open weights: `Wren.mlmodel` + `Wren.pt` (PyTorch) + `Wren.config.json` (framing/norm/threshold) + model card.

---

## 4. App integration (`apps/desktop`, PR #48, branch `feature/wren-backend`)

- **Data-driven catalog** `FillerModelCatalog` (reuses `ModelSpec`): add a model = one entry; disable = remove it. No hardcoded `if model == …`.
- **Settings** (`EngineConfig`/`EngineSettings`): `fillerModelEnabled` (opt-in, **off by default**), `selectedFillerModelID`, `shareFillerData`. Forward-compatible.
- **Engine seam** (`pipeline.py`): `--filler-backend {whisper,coreml}` + `--filler-model`. The single filler call branches to `detect.filler_words()`, which shells out to the bundled `crisp-filler` helper (`CRISP_FILLER`) and returns spans tagged `"um"` so the rest of the pipeline (is_filler → cut → render) is unchanged. Whisper path is byte-for-byte unchanged when off.
- **The helper** `crisp-filler` (`Sources/crisp-filler/main.swift`): reads WAV → log-mel via **Accelerate `vDSP_mmul`** (the DFT as a matrix multiply — n_fft=400 isn't a power of two, so vDSP's FFT can't be used; matmul-DFT is exact) → Core ML → threshold + merge → JSON. **Parity-verified vs `infer.py`: 66/66 intervals, 0.000 s diff.** Bundled+signed in `engine/bin` by `build.sh`.
- **UI** (`SettingsView` "Filler detection (experimental)"): opt-in toggle + data-driven picker + `ModelInstallControl`. Shows an **English-only / experimental warning** when enabled. Whisper's "Speech model" picker is **hidden when Wren is on** (mutually exclusive). Model-aware gating in `ContentView`.
- **Feedback (step 5)** `FillerFeedback`: opt-in, anonymous, **on-device** JSONL in `~/.crisp*/feedback/` (model + counts + durations; never audio/filenames; nothing uploaded). *Foundation only* — see "data collection later" below.

---

## 5. Issues found in real-world testing (the important part)

First real production-video test (a ~20-min talking-head recording in `~/Movies`) surfaced three problems:

- **Over-cutting.** Removed ~5:53 (≈25–30% of the video). Way too much.
  - **Root cause:** trained on PodcastFillers, where examples are 1-s clips ~50/50 filler/not. The model's internal prior expects ~50% fillers, but real video is ~95% speech. A small per-chunk error rate × thousands of chunks = minutes of false cuts. **Training-distribution mismatch.**
- **Cuts natural mid-sentence "hmm"s.** A brief hesitation *inside* a flowing sentence (part of natural delivery) gets cut, which **breaks the sentence**.
  - **Root cause:** the model classifies *sound*, not *meaning*. It can't tell a removable standalone "uhh" from a load-bearing mid-thought "hmm". (Whisper differs: it only cuts a sound it *transcribes* as the word "um"/"uh", so it's more conservative.)
- **Rough cuts.** Coarse ~0.1 s boundaries (can land mid-syllable) + tight cuts + cutting mid-flow → jarring jumps.
- Side effects: slow **render** at the end (more cuts → more segments → slower ffmpeg concat); fans ramp but far less than whisper (no transcription).

---

## 6. Fixes

### Tier 1 — quick levers (DONE, no retraining)
- **Higher threshold:** helper default `0.7 → 0.85` (real video is word-dominated; favor precision; benchmark P≈0.97 at high thresholds).
- **Min filler length:** helper `minFiller 0.08 → 0.30 s` (a real "uhh" is longer; drops fleeting blips).
- **Silence-gating** (`edit.gate_fillers_by_silence`, applied in `pipeline.py` only for the coreml backend): keep a filler **only if** it's clearly long (`FILLER_MIN_SOLO=0.5 s`) **or** sits at a pause boundary (`FILLER_PAUSE_PAD=0.2 s` from a silence edge). Drops brief fillers embedded mid-speech — the mid-sentence-hmm fix.
- Effect on the (artificial, pause-free) demo: **64 → 16 fillers, 31 s → 11 s cut.** Real footage (with real pauses) should improve more.

### Per-model values are config-driven (not hardcoded) — important
- **Problem:** different models need different threshold / min-length / framing / norm. Hardcoding them in the `crisp-filler` helper breaks at model #2 (e.g. Kestrel).
- **Design — three layers, each overrides the one above:**
  1. **Built-in defaults** in the helper (= Wren's values; sensible baseline so it runs standalone).
  2. **The model's `config.json`** (published next to the model on HF) — per-model recommended values, loaded WITH the model. `crisp-filler --config <model>.config.json`.
  3. *(future)* per-clean user override (a "how aggressive" slider) for footage-level tuning.
- **Flow:** app downloads `<name>.config.json` beside the model (`FillerModelConfig.fetchIfNeeded`) → engine (`detect.filler_words`) passes `--config` if present → helper `Spec.load()` overrides its defaults. The whole chain is model-agnostic; adding a model = upload `.mlmodel` + `config.json` with ITS values + one catalog entry.
- `Wren.config.json` carries `recommended_threshold=0.85`, `min_filler=0.30` (the Tier-1 values). Republished as **v0.0.7** (model weights unchanged; catalog points there).
- Silence-gate knobs (`FILLER_MIN_SOLO`/`FILLER_PAUSE_PAD`) are engine-side `config.py` (cut-smoothness, fairly model-agnostic) — could move into per-model config later if needed.

### Model update system (like the app updater, but from Hugging Face)
- **Goal:** push a new model to HF → users get an in-app update banner → download the new model + config, independent of app releases.
- **Manifest = `config.json` on `main`.** Carries `version` + **`model_sha256`** (added to `publish_hf`) + the recommended values. The `main` ref always points at the latest, so polling it = "what's the newest?".
- **`FillerModelUpdater.check()`** fetches the manifest, compares `version` to the installed one (`FillerModelConfig.installedVersion`, read from the local config sidecar), and if newer builds an `updateSpec` (URL pinned to the new `vX`, **sha from the manifest** → the update is verified like a first install).
- **UI:** an "Model update available — vX → Update" row in the filler Settings section. Update action: remove old config sidecar → `ModelStore.applyUpdate(to:)` (evicts the stale id-keyed provisioner, removes old file, downloads+verifies new) → CrispApp's ready-task re-fetches the new config.
- **Checked on launch** (when the model is installed + the feature is on).
- **Dev workflow:** train → export → `publish_hf` (bumps `v0.0.N`, updates `main`) → app sees it and offers the update. No app rebuild needed to ship a new model. (The catalog's pinned URL is just the baseline/first-install version.)

### Tier 2 — the real fix (TODO, retraining)
- **Deployment-matched diet:** far more *negative* (normal-speech) examples + **hard negatives** (the exact mid-sentence hmms and filler-like words it confuses). Recalibrates the prior.
- **Train on continuous audio**, not event-centered 1-s clips, so it learns context.
- **Augmentation** (noise, varied speakers/mics) for robustness.
- Optionally fold in SEP-28k (NC license → experiments only) for more/varied negatives.
- Then re-export → publish `v0.0.N` → bump the one `ModelSpec` line.

### Data collection (later)
- Current `FillerFeedback` only logs anonymous stats **locally**; nothing reaches the developer yet.
- To make it useful: capture **review-timeline corrections** (which predicted cuts the user kept/removed = labeled data) + an explicit, consented upload to a small endpoint. Needs a backend + privacy review.

---

## 7. Quick reference

- Branch: `feature/wren-backend` → PR #48 (into `nightly`).
- Try it: Crisp Dev → ⌘, → Cutting → enable filler model → Install Wren → clean a video.
- Helper CLI: `crisp-filler --model Wren.mlmodel --audio in.wav [--threshold 0.85]`.
- Engine: `clean_video.py … --filler-backend coreml --filler-model Wren.mlmodel` (set `CRISP_FILLER`).
- Tunables: `Spec.defaultThreshold`/`minFiller` in `main.swift`; `FILLER_MIN_SOLO`/`FILLER_PAUSE_PAD` in `crisp/config.py`.
