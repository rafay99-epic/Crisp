---
id: doc-6
title: Research notes
type: other
created_date: '2026-07-01 19:33'
---


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
  python -m filler_classifier.v1.train --dataset podcastfillers --data data/PodcastFillers --epochs 30
  python -m filler_classifier.v1.evaluate --dataset podcastfillers --data data/PodcastFillers --split test
  python -m filler_classifier.v1.infer some.wav --threshold 0.7        # reference impl
  ```

### Export + hosting
- Export to a **single-file Core ML `.mlmodel`** (neuralnetwork) in a **Python 3.10** env (`.venv-export`; coremltools' BlobWriter has no Py3.14 build).
  ```sh
  ./.venv-export/bin/python -m filler_classifier.v1.export_coreml   # → checkpoints/Wren.mlmodel
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
- **Manifest = `config.json` on the channel's branch** (see ML dev flow). Carries `version` + **`model_sha256`** (added to `publish_hf`) + the recommended values. The branch's tip always points at the newest model on that channel, so polling it = "what's the newest for me?".
- **`FillerModelUpdater.check()`** fetches the manifest, compares `version` to the installed one (`FillerModelConfig.installedVersion`, read from the local config sidecar), and if newer builds an `updateSpec` (URL pinned to the new `vX`, **sha from the manifest** → the update is verified like a first install).
- **UI:** an "Model update available — vX → Update" row in the filler Settings section. Update action: remove old config sidecar → `ModelStore.applyUpdate(to:)` (evicts the stale id-keyed provisioner, removes old file, downloads+verifies new) → CrispApp's ready-task re-fetches the new config.
- **Checked on launch** (when the model is installed + the feature is on).

### ML dev flow — model channels mirror the app's release channels

The same problem the app solves with dev/nightly/stable, for models: **don't push a freshly trained model straight to Stable users, and keep old models reachable in dev.** All three pieces reuse what already existed (the `ModelSpec` download/verify stack, `versionedURL`, `applyUpdate`).

- **HF repo `rafay99-epic/crisp-models` is branched per channel** (decision: branch-per-channel):
  - `main` branch → **Stable** manifest. `nightly` branch → **Nightly + Dev** manifest.
  - `Channel.modelChannelRef` (`main` on Stable, `nightly` on Nightly/Dev) is the only thing that changes which manifest the app polls — `FillerModelUpdater.manifestURL` reads it. Everything else (download by global `v0.0.N` tag, verify by sha) is identical.
- **Publish = staging by default.** `publish_hf.py --channel {nightly,stable}` (default **nightly**) commits to that branch + tags `v0.0.N` (commit-count, counted on `nightly` so it's one monotonic line). Nightly/Dev apps offer the update immediately; Stable can't see it.
- **Promotion = `promote_model.py`** (the model mirror of `.github/scripts/promote.sh`): copies the nightly tip's files onto `main` in **one commit** (no branch merge → no 3-way-merge conflict). Flips the manifest's `channel` marker to `stable`. `--version vX` promotes/rolls back to a specific tag. Pin the catalog floor to the promoted version afterwards.
- **Local sideload (the `./dev.sh` of models)** — `DevFillerModel` (CrispCore), **dev build only**: run a `.mlmodel` straight from disk *before* publishing anything. Resolves from `$CRISP_FILLER_MODEL` (scripted) or a Settings → "Load local model…" picker. Put `<name>.config.json` beside it (export writes one) so framing/threshold travel. Gating (`fillerModelReady`), the engine `--filler-model`, and the status banner all follow the override; a stale picked path silently falls back to the downloaded model.
- **Version history (the git-history of models)** — `FillerModelVersions` (dev build only): lists the repo's `v0.0.N` tags via the HF refs API (`/api/models/<repo>/refs`) and installs any one (pinned + sha-verified from that version's own `config.json`). Lets you A/B an old model against a new one in Dev. The history already exists server-side — every publish is an immutable tag.
- **Wiring:** `Channel.showsModelDevTools` (== dev) gates both dev affordances; `CrispApp` owns `FillerModelVersions`; the two dev sections live under a "Developer" divider in the filler Settings section.
- **Tests:** `FillerModelDevFlowTests` — channel→branch mapping, the HF URL helpers (now `nonisolated`), dev-tool gating, sideload inert off-dev.

### Tier 2 — the real fix (TODO, retraining)

- **Deployment-matched diet:** far more *negative* (normal-speech) examples + **hard negatives** (the exact mid-sentence hmms and filler-like words it confuses). Recalibrates the prior.
- **Train on continuous audio**, not event-centered 1-s clips, so it learns context.
- **Augmentation** (noise, varied speakers/mics) for robustness.
- Optionally fold in SEP-28k (NC license → experiments only) for more/varied negatives.
- Then re-export → `publish_hf --channel nightly` → test in Crisp Dev (sideload first, even) → `promote_model` → bump the catalog floor. Ships as a model update; **no app change** (this is the whole point of the dev flow above).

### Data collection (later)
- Current `FillerFeedback` only logs anonymous stats **locally**; nothing reaches the developer yet.
- To make it useful: capture **review-timeline corrections** (which predicted cuts the user kept/removed = labeled data) + an explicit, consented upload to a small endpoint. Needs a backend + privacy review.

---

## 6b. Wren v2 — the context-aware model (BUILT, works on real footage)

The Tier-2 plan above, executed. `feature/wren-context-model`. **Verified on real footage: removed 4:04 of fillers, cuts spot-on, kept natural speech — whisper-free** (engine log confirms `filler exited 0`, zero whisper lines).

**The reframe.** v0.0.8 answered "is there an um *sound* here?" (250 ms, no context) → over-cut (17.6% of audio). v2 answers "is this a **removable** filler?" — needs context, so it keeps natural mid-sentence "hmm"s.

**Phase 0 — labels (`derive_labels.py`, `validate_labels.py`).** PodcastFillers gives per-episode filler timing + a 10 ms VAD signal. Bucket each Uh/Um by pause-adjacency: **isolated** (silence both sides → REMOVABLE), **boundary** (one side → gray), **embedded** (buried in speech → NATURAL). 34,985 labeled fillers. Acoustic gradient confirms separability: mean duration NATURAL 0.35 → boundary 0.39 → REMOVABLE 0.46 s. Cross-checked vs the real engine `silencedetect` on 20 episodes: pause-adjacency by bucket **46% / 21% / 1.7%** — the critical NATURAL "don't-cut" label agrees with the shipped pause logic **98.3%**. (whisper validation was a dead end — base.en/large both *drop* most fillers in transcription, i.e. whisper has low filler recall: that's *why* it feels smooth = it under-cuts.)

**Phase 1+2 — model + pipeline.**
- `model_v2.WrenSeq` — tiny **dilated TCN** (~129k params) over a log-mel sequence → per-frame P(removable). Fully convolutional (~2.5 s receptive field): trains on 4 s windows, runs over a whole recording in one pass. Chosen over GRU for clean Core ML export.
- `preprocess_v2` — mp3 → cached float16 log-mel + a window index. Positives = windows around removable fillers; negatives include windows centered on NATURAL/boundary fillers as **hard negatives** (this is *how* it learns to keep natural fillers). `WINDOW_SEC=4`, `NEG_PER_POS=3`, `HARD_NEG_FRAC=0.5` in `config.py`.
- `dataset_v2.SeqWindows` — serves (mel window, per-frame label) from the cache. `train_v2` — per-frame BCE + pos_weight, MPS-accelerated, val P/R/F1.

**Results.** 66 train / 6 val episodes (partial download), 40 epochs. Best val **F1=0.74 @ thr 0.95** (P 0.67 / R 0.82); recall stays ~0.9 across thresholds. Precision is *pessimistic* — only isolated (17%) labeled positive, so firing on a boundary filler (a real cut) scores as a false positive. `infer_v2 --compare` on a 48-min episode: v0.0.8 cut **17.6%** (1386), v2 cut **1.0%** (86). Operating threshold **0.9**.

**Phase 4+5 — inference + ship path.**
- `infer_v2.py` — whole-recording inference → spans, `--compare` runs v0.0.8 on the same audio.
- `export_coreml_v2.py` — flexible-length single-file `.mlmodel` (input `mel` [1,n_mels,T] → `removable_prob` [1,T], sigmoid folded). PyTorch↔CoreML parity ~1e-7. Also writes the self-describing `config.json` (`model_type:"sequence"`, `generation:2`).
- **Helper (`crisp-filler/main.swift`) is now data-driven** — reads `model_type` from config and runs `chunk` (v0.0.8) or `sequence` (v2). Mel frontend shared; old config with no `model_type` → chunk, unchanged. **Swift helper ↔ PyTorch reference produce identical spans.**
- Built models live in **`research/models/wren-v2/`** (in repo, gitignored, never pushed; published to HF instead).

**Shipping order (IMPORTANT — coupling).** v2 needs the new sequence-capable helper, so it is **not** a pure model-only update. Order: (1) merge `feature/wren-context-model` → nightly (app gets the helper), (2) `publish_hf` for v2 config, (3) publish v2 → HF nightly as `v0.0.9`, test in Crisp Nightly, (4) promote to stable. An old helper would mis-run a sequence model, so the model must not reach a channel before its helper does.

**Capability tie — captions.** The custom model detects filler *audio* only; it can't transcribe, so **captions (SRT/VTT) are a whisper-only feature** — the single on-shelf-model tie (pauses via `silencedetect`, fillers, encoding all work with the custom model). When the fast filler model is on, captions are **hard-disabled** in Settings (warning: *"This feature might not be available with our custom fast model"*) and dropped in `CleanRunner` for *every* entry point (per-row presets, watcher, Shortcuts) — so the engine never silently bypasses the fast model to run whisper just for captions. Previously `pipeline.use_classifier = … and not want_captions` would do exactly that silently.

**Logging.** Every model switch is logged (`AppInfo.logger("model")`: speech-model select, filler enable/disable/select/sideload/version-install) and every clean records its backend + the exact model identity (name + version + chunk/sequence + gen) across app → engine → helper, plus the helper's per-run diagnostics (threshold/frames/spans/ms). So the daily log answers *which model ran, with what settings, how fast*.

**Next / iterate (real-life loop).** More footage → tune threshold (config `recommended_threshold`) or retrain folding boundary fillers in for recall; more episodes (we have 66/174) + FluencyBank (held-out test) + SEP-28k (hard-neg variety); the engine silence-gate (`FILLER_MIN_SOLO`/`PAUSE_PAD`) is now a light safety net on top of an already-precise model — could relax it.

---

## 6c. v3 experiments — what moves accuracy (and what doesn't)

Two cheap experiments to find the real accuracy lever — both on the SAME tiny model (architecture unchanged), to test "data/labels over architecture."

**Re-labeling (transcript-grounded) — NO CLEAR WIN.** `v2/relabel.py` uses PodcastFillers' episode transcripts (Azure ASR, word-level timing) to define removability by *language*, not just VAD: a filler tightly bracketed by spoken words on both sides can't be cleanly cut → natural; one with a real word-gap → detachable → removable. The labeling *definition* swings the positive rate enormously — "detached on one side" = **72%** removable (over-cuts), "both sides" = **20%** (conservative, ~v2). At the conservative rate the transcript only rescued ~1,180 fillers VAD missed, and the retrained model was statistically indistinguishable from v2 on held-out episodes. **Lesson: label cleverness at the conservative point is not the lever; "should cut" is an editorial judgment, not a mechanical one.**

**Hard negatives (SEP-28k) — WORKS, consistent win.** The behavioral test exposed the real error: on a music episode v2 cut ~30 spans, only ~1 a real filler (**3% on-filler**) — it fires on non-speech because it only trained on PodcastFillers (clean speech + fillers). `v2/hard_negatives.py` pulls SEP-28k non-interjection clips (Music, NoSpeech, other disfluencies, clean speech) as **all-negative** windows; `train --hard-neg` mixes them in. Result on 4 held-out episodes vs v2: **on-filler precision up on all four** (63→69, 47→55, 77→81%), **fewer spans on all four** (cuts less, more precisely). The music episode barely moved (3→4%) — only 156 Music + 239 NoSpeech clips available; **scaling non-speech negatives is the next iteration.** v2+hardneg is strictly better than shipped v2 → candidate **Wren v0.0.10** after scaling negs + footage validation. Built model: `research/models/wren-v2-hn/`.

**Direction for v3.** (1) Scale hard negatives (music/noise/no-speech) — the proven lever. (2) Fine-tune on the user's own footage (domain). (3) Keep v2's conservative labels — proven near-optimal. (4) **Two tiers:** **Wren** (light, audio-only, fast) stays the daily driver; a heavier **Raven** (audio **+ transcript** → real language understanding, slower — runs ASR, learns the editorial removability decision, beats raw whisper which under-cuts) is where the intelligence lives. The data-driven helper (`model_type`) + catalog + `canRun` guard already support shipping both side by side.

---

## 6d. Tier-A training recipe (SpecAugment + focal loss + cosine LR) — WASH (PR #62)

Trained **baseline vs Tier-A on the SAME data** (`labels_v2` + `data/hardneg`), 40 epochs each, as a clean A/B. The recipe flags live in `v2/train.py`/`v2/dataset.py` behind `--spec-augment --focal --cosine` (default off).

**Result — essentially no win.**
- Validation best-F1 (each at its own optimal threshold): **baseline 0.747 @thr 0.95** vs **Tier-A 0.754 @thr 0.80**. +0.007 is noise.
- Focal loss **re-calibrated** the model (more confident/peaked): its operating point shifted 0.95→0.80, and it's **brittle** above 0.80 (recall collapses — R=0.36 @0.90, ~0 @0.95). Baseline's P/R curve is smoother/more forgiving.
- Behavioral on the synthetic music/noise clips (`~/Movies/CrispModelTest`), each at its best threshold: both still over-fire ~equally (music 6 vs 5 cuts on 29 s; noise 6 vs 6 on 19 s). **Tier-A did NOT fix non-speech over-firing.**

**Lesson — confirms "data over architecture" again.** SpecAugment/focal/cosine are *training-recipe* tweaks; the weakness (firing on music/noise) is a **data-coverage** problem — both runs used the same thin negative set (156 Music + 239 NoSpeech). No training trick teaches the model about audio it's barely seen. So: **keep the flags** (free, slightly tighter — turn them ON once data is scaled) but **don't ship a model from Tier-A alone.** The lever is still negative-class coverage, not the recipe.

**Next — Tier B (the real lever): scale the negatives.** Two complementary routes, both permissively licensed:
1. **Synthetic mixing** — overlay speech with music (FMA = CC, MUSDB18) + noise (ESC-50) at varied SNR → unlimited "don't-cut" negatives covering the exact failure mode. `v2/synth_negatives.py` (TODO).
2. **Teacher-labeled data (distillation-flavored)** — use a big pretrained audio model (AudioSet tagger / PANNs, or Whisper's encoder) to auto-label oceans of *unlabeled* audio as speech/music/noise → generate vast negatives at scale, distill into tiny Wren. The scalable version of "more data" — the teacher *produces* the data. (See MODEL_RESEARCH §1 Tier-3, §3.4-I.)

Then retrain **with the Tier-A flags on** (they're free) and re-measure on real footage. Right amount of data = watch the held-out val F1 for over/under-fit; the gap today is the negative class being *narrow*, not the dataset being too small.

---

## 7. Quick reference

- Branches: `feature/wren-backend` → PR #48 (merged into `nightly`); `feature/ml-dev-flow` = the model dev flow (channels + sideload + history).
- Try it: Crisp Dev → ⌘, → Cutting → enable filler model → Install Wren → clean a video.
- Helper CLI: `crisp-filler --model Wren.mlmodel --audio in.wav [--threshold 0.85]`.
- Engine: `clean_video.py … --filler-backend coreml --filler-model Wren.mlmodel` (set `CRISP_FILLER`).
- Tunables: `Spec.defaultThreshold`/`minFiller` in `main.swift`; `FILLER_MIN_SOLO`/`FILLER_PAUSE_PAD` in `crisp/config.py`.
- **Ship a new model:** `python -m filler_classifier.publish_hf --repo rafay99-epic/crisp-models --model …/Wren.mlmodel --weights …/filler_cnn.pt --card …/MODEL_CARD.md` (→ nightly) → test → `python -m filler_classifier.promote_model --repo rafay99-epic/crisp-models` (→ stable).
- **Sideload (no publish):** `CRISP_FILLER_MODEL=…/Wren.mlmodel open 'Crisp Dev.app'`, or Settings → "Load local model…". Dev build only.
- **One-time HF seed:** the `nightly` branch is auto-created on first `--channel nightly` publish (forked off `main`). Until then Nightly/Dev just see no update (manifest 404 → handled).

### Wren v2 (context model) — `feature/wren-context-model`
- Labels: `python -m filler_classifier.v2.derive_labels` then `… validate_labels --limit 20` (engine cross-check; `--whisper` for the recall insight).
- Train: `… preprocess_v2 --splits train validation` (once, caches mels) → `… train_v2 --epochs 40` (best → `checkpoints/wren_seq.pt`). Use `.venv`.
- Test on real footage: `… infer_v2 "/path/video.mp4" --compare` (v2 vs v0.0.8 cut time, side by side).
- Export: `./.venv-export/bin/python -m filler_classifier.v2.export_coreml` → `research/models/wren-v2/Wren.mlmodel` + `Wren.config.json`.
- Try in app: Crisp Dev → ⌘, → Cutting → enable filler model → Developer → "Load local model…" → `research/models/wren-v2/Wren.mlmodel`.
- Tunables: `WINDOW_SEC`/`NEG_PER_POS`/`HARD_NEG_FRAC` in `config.py`; per-model `recommended_threshold`/`min_filler` in the exported `config.json`.
