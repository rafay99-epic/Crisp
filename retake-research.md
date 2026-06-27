# Retake detection — research findings & chosen direction (living doc)

Deep-research synthesis on how to push retake detection beyond the current
verbatim-repeat + pause-anchor baseline, with a focus on what's **viable to ship**
in a local-only, Apple-Silicon, indie macOS app. Read alongside `notes.md`,
`retake-calibration.md`, and the `retake-removal` memory.

> Source: a multi-source web-research pass (dozens of searches + source reads,
> each claim independently cross-checked; only 1 claim was refuted on review).

## Bottom line
No off-the-shelf component solves this. Shipping leaders (Descript, TimeBolt) top
out ~90% F1 on **clean scripted** retakes and **crater to 66–81% on natural,
filler-heavy speech** — and **every one keeps a human in the loop; nobody silent
auto-cuts.** Mid-sentence restarts with **no pause and no marker** (Abdul's exact
case) are the single hardest category for *every* technique surveyed, including SOTA
acoustic models. **Fully-trusted silent auto-cut of natural retakes is not
achievable today — by anyone.** Realistic goal: raise candidate recall, aggressively
cut false positives via signal-agreement, and surface high-confidence suggestions.

## Angle 1 — Is Whisper the right ASR?
- **Vanilla Whisper is actively wrong here.** It's trained to produce fluent text, so
  it deletes fillers/hesitations/false starts on purpose — and an un-transcribed
  disfluency also **corrupts the timestamp of the following word**, so even surviving
  retakes can get wrong cut boundaries. (whisper-timestamped docs.)
- **CrisperWhisper** (arXiv:2408.16589, INTERSPEECH 2024) — Whisper-arch model
  fine-tuned to transcribe *verbatim* incl. fillers/stutters/false starts, precise
  word timestamps. Beats Whisper on verbatim WER (6.66 vs 7.7). **BUT: CC-BY-NC 4.0
  (non-commercial — blocks a paid app) and no whisper.cpp / Core ML build exists.**
  Best signal, currently blocked.
- **whisper-timestamped** `detect_disfluencies=True` + `condition_on_previous_text`
  off makes Whisper less fluent — but the `[*]` it emits is a **placeholder marker,
  not recovered text**. Surfaces *that* a disfluency happened, not *what was said*.
- Alt ASR (Parakeet, Wav2Vec2): verbatim *behavior* matters more than base WER.

**Verdict: HIGH payoff, MED-HIGH effort. Root-cause fix. Near-term: disable
context-conditioning + use word confidence. Medium-term: verbatim ASR is gated on
licensing/conversion.**

## Angle 2 — Disfluency detection / speech repair (reparandum–interregnum–repair)
- Mature task, high-accuracy **open** models — but transcript-based and trained on
  the wrong domain.
- **pariajm/joint-disfluency-detector-and-parser** (ACL 2020, **MIT**): self-attentive
  BERT, **EDITED-word F1 ~90.8% (92.4% w/ self-training)**. Pretrained downloadable.
  *Caveat: full BERT parser, PyTorch+Cython → Core ML conversion is real work.*
- **Small BERT (arXiv:2104.10769, Rocholl):** disfluency taggers as small as
  **1.3 MiB** — *a paper result, NOT a released artifact.* Purpose-built on-device,
  supports the idea that a tiny Core ML tagger is feasible **if we train one.**
- **LARD** (NAACL 2022) generates synthetic disfluencies **incl. restarts** from
  fluent text — the path to fight the domain gap.
- **Domain gap (recurring):** standard corpus is Switchboard (~6% disfluent, restarts
  rare) — phone calls, not talking-head video. High Switchboard F1 ≠ high accuracy on
  Abdul's restarts. And transcript-based detectors **cannot recover what the ASR
  already deleted** — they're bottlenecked by Whisper.

**Verdict: MED payoff, MED effort. Real/open/convertible models exist, but only see
what the ASR kept (pair w/ Angle 1), risk domain shift. Use as a precision filter on
candidates, not a primary detector.**

## Angle 3 — Semantic: genuine redo vs. intentional parallel structure
- **Apple `NLContextualEmbedding`** runs on-device, **512-dim on macOS** (corrected
  below — and it downloads an OS asset on first use, so not strictly zero-download),
  cosine via Accelerate. Needs macOS 14+. *Caveat: noisy on short inputs (single words
  0.60–0.89 even when unrelated) — use phrases.*
- **swift-embeddings** (MIT) — real sentence-transformers (MiniLM, nomic) in Swift via
  MLTensor, the upgrade if NLEmbedding is too weak.
- **mlx-swift** — higher ceiling, incl. a small on-device "retake judge" LLM (llama.cpp
  — sibling of the whisper.cpp we already ship — is a viable runtime).
- **The threshold ceiling:** best paraphrase model (MPNet) only 75.6% acc / F1 0.836 at
  an *optimized* cosine threshold — **no universal cutoff; task/model dependent.**
  Paraphrases AND parallel structure both score high → similarity must be **one signal
  combined with anchors**, never a standalone gate.

**Verdict: MED-HIGH payoff, LOW-MED effort. Most attractive incremental win — directly
attacks the parallel-structure false-positive, ships with no new binaries. Corroborating
signal only.**

## Angle 4 — Acoustic / prosodic (false starts that leave no text)
- Prosody genuinely carries the restart signal text loses (pitch reset, pre-boundary
  lengthening) — but research-grade, feature-engineering-heavy.
- Hybrid (text + prosody) beats text-only (NAACL 2018) — prosody should **confirm/reject
  a textual hypothesis**, not replace it.
- Acoustic-only (arXiv:2311.00867, WavLM/HuBERT, F1 0.86–0.88) **performs WORSE on
  REVISIONS and RESTARTS** — Abdul's exact category is the hardest even here; trained on
  clinical stutter corpora, not video.
- Repeated-waveform self-similarity (ICASSP 2009): candidate generator, degrades on
  noise — not a precise cutter.

**Verdict: LOW-MED payoff, HIGH effort. Only thing that catches text-less restarts, but
weakest on restarts specifically. Use as a corroborating vote later, never a trigger.**

## Angle 5 — Existing products / OSS
- **Descript "Remove Retakes":** auto-detects re-recorded phrases + false starts, marks
  earlier versions as **non-destructive "ignored text"** to restore/delete. Suggest-and-
  confirm. No algorithm disclosed.
- **TimeBolt** (closest analog — runs locally): word/sentence repeat matching, **keeps the
  LAST take**, scored with **Jaccard + edit distance** (fuzzy, not verbatim). **Waveform
  engine runs first** (dead air), transcript AI second, cross-validated. Tunable
  **look-ahead window (5–50 lines)** is the precision lever; unscripted false starts caught
  by segmenting at **pauses ≥0.8s**.
- **Ceiling benchmark (vendor self-reported, treat with caution):** TimeBolt 90.6% F1
  (96.8% P / 85.5% R); Descript 80.4%. **On filler-heavy speech: TimeBolt 81%,
  Descript 66%. "Human verification remains necessary for all three."**

**Verdict: HIGH payoff as a blueprint. Validates our direction: verbatim→fuzzy matching,
tunable look-ahead, waveform cross-validation, suggest-and-confirm.**

## Weak / flagged claims
- The "1.3 MB model" is a paper result, **not a downloadable artifact**. The confirmed MIT
  model is a bigger PyTorch+Cython parser.
- All product accuracy numbers are vendor self-benchmarks (no methodology). Relative
  ranking (hybrid > transcript-only; all crater on natural speech) is more trustworthy.
- Domain mismatch is pervasive and under-quantified — no source measured restart detection
  on the actual talking-head-video domain.
- A disfluency tagger on Whisper **cannot recover the "open source" case** if Whisper
  smoothed those words away (Problem 2). Needs verbatim ASR or audio.

## Chosen direction (agreed with Abdul)
**Tier 1 + Tier 2 combined, run alongside Whisper when retakes are enabled.**
1. Whisper transcript → **fuzzy** candidate matching (edit-distance/Jaccard, look-ahead
   window) — high recall.
2. **Apple `NLContextualEmbedding` semantic gate** — same-intent? kills parallel-structure
   FPs.
3. **Disfluency model** (Tier 2) — precision filter (exact shippable artifact TBD; bake if
   tiny, else download via ModelStore).
4. Existing zero-cross snap + fade + segment-merge → fluid splice.

**UX — one feature, three trust levels** (default = simplest):
- **Automatic** (default) — silent confident cuts, like pauses/fillers. For the "just clean
  it" user.
- **Review** — auto-cut but **restorable** + sensitivity knob. For the tinkerer.
- **YOLO / Full-send** — aggressive recall, trust it fully. For the power user.

**Sequencing:** (1) build Tier 1 now (no new binaries, validate on real footage + build the
5–6 example test set the notes require); (2) verify the real Tier 2 artifact (license /
Core ML / size) before bake-vs-download; (3) add Tier 2 + the three UX modes.

**Honest ceiling:** target precise, fluid, trustworthy *suggestions* that beat the current
baseline — not magic invisible perfection, which no one ships.

## Tier 2 artifact verification (follow-up — supersedes optimistic notes above)
A focused second pass on what disfluency model is *actually* shippable:
- **pariajm joint detector (MIT): NOT VIABLE.** It's a self-attentive BERT *parser*
  (reads disfluencies off `EDITED` parse-tree nodes), hundreds of MB to ~1 GB, legacy
  PyTorch 0.4–1.1 + Cython + EVALB, no ONNX/Core ML export. Great F1 (92.4), unshippable.
- **The "1.3 MB" model is PAPER-ONLY (Rocholl/Google, Interspeech 2021).** No code, no
  checkpoint. The figure = a small-vocab BERT (6L×96h, ~1.2M params, 5k vocab) int8-
  quantized via TFLite; F1 88.4 on Switchboard. It's a recipe to **train our own**, not
  a download. ⇒ the "bake in the 1.3 MB model" idea is invalid as stated.
- **hafidev/bert-...-disfluency-detection-beta (Apache-2.0):** the only real off-the-shelf
  permissive tagger; converts to Core ML cleanly, BUT bert-base-sized (~110 MB int8) and
  **unvetted beta** (no standard-benchmark eval). Usable as a quick experiment only.
- **LARD synthetic restart generator:** DOES generate restarts (ideal), pure-Python light
  deps — BUT **code is CC BY-NC-SA (non-commercial)**, dataset CC BY-SA (ShareAlike).
  ⇒ reimplement its simple rule-based logic ourselves to train on permissive data.
- **Apple `NLContextualEmbedding` correction:** **512-dim** (not 768), macOS 14+, and it
  **downloads an OS-managed asset on first use** (needs network once — like the whisper
  model already does), NOT zero-download. Truly-offline bundled fallback = `NLEmbedding`
  sentence embeddings (older macOS, but non-contextual / weaker).

**Net effect on the plan:** Tier 2 is **not** a tiny-file bake-in — it's either (a) ship the
~110 MB unvetted hafidev model to test the concept, or (b) **train our own small Core-ML
tagger** (Rocholl recipe + self-reimplemented LARD restart data) — a real ML project on the
order of the Wren classifier (= `ml-custom-models` #3). Decision deferred until Tier 1 +
real-footage validation shows the ceiling actually needs it. Tier 1 (fuzzy + Apple semantic
gate) remains the cheap, correct first move.
