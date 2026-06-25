# Wren/Raven — Model Research & Improvement Roadmap

Research by Scarlet Speedster for the Crisp filler-detection model pipeline.
Covers: state-of-the-art ASR models better than Whisper, public datasets for
training, and techniques to make Wren/Raven beefier, stronger, and more accurate.

---

## 1. State-of-the-Art ASR / Speech Models (Better Than Whisper)

Wren's current approach — a tiny CNN (~75k params for v0.0.8, ~129k for v2) — is
intentionally minimal. But for the heavier **Raven** tier (audio + transcript),
here are the models worth considering, ranked by relevance to Crisp's use case.

### Tier 1 — Direct candidates for Raven

| Model | Size | WER (English) | Speed | Why it matters for Crisp |
|---|---|---|---|---|
| **NVIDIA Canary-Qwen-2.5B** | 2.5B | **5.63%** (Open ASR Leaderboard #1) | 418 RTFx | SALM architecture (ASR + LLM). The LLM decoder could learn the "editorial removability" decision that Wren can't — exactly what Raven needs. |
| **NVIDIA Canary-1B-v2** | 1B | ~6.4% | Faster than Whisper Large | Pure ASR, multilingual. Good baseline for transcript generation that feeds into Raven's removability classifier. |
| **NVIDIA Parakeet-TDT-0.6B-v3** | 0.6B | ~6.5% | **2793 RTFx** (40x faster than Whisper) | If speed matters for Raven, this is the fastest quality ASR model available. Non-autoregressive — no token-by-token generation. |
| **Distil-Whisper Large v3** | ~750M | Within 1% of Whisper Large | **6x faster, 49% smaller** | If you want to stay on the Whisper family but faster. Good for the transcript step without the full Whisper overhead. |

**HuggingFace links:**
- `nvidia/canary-qwen-2.5b` — https://huggingface.co/nvidia/canary-qwen-2.5b
- `nvidia/canary-1b-v2` — https://huggingface.co/nvidia/canary-1b-v2
- `nvidia/parakeet-tdt-0.6b-v3` — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- `distil-whisper/distil-large-v3` — https://huggingface.co/distil-whisper/distil-large-v3

### Tier 2 — Alternative architectures

| Model | Size | WER | Notes |
|---|---|---|---|
| **Qwen3-ASR-1.7B** | 1.7B | Competitive | 52 languages, built on Qwen3-Omni. Jan 2026 release. |
| **Voxtral** (Mistral) | ~3B | Competitive | Multimodal speech understanding, can do Q&A on audio content. |
| **IBM Granite-Speech-3.3** | ~3B | Top-tier | Conformer encoder + LLM decoder, same architecture class as Canary-Qwen. |
| **wav2vec2-large-960h-lv60-self** | ~317M | ~1.8% (LibriSpeech) | Facebook. Good for feature extraction / transfer learning. |

**Key insight for Crisp:** The Conformer+LLM architecture (Canary-Qwen, Granite-Speech) is the current SOTA. For Raven, the LLM decoder's language understanding could directly learn the "should this filler be cut?" editorial decision — which is exactly the problem Wren's sound-only approach can't solve.

### Tier 3 — Whisper encoder for feature extraction (not full ASR)

Recent papers (WhisPAr, Whilter) show that **Whisper's encoder** can be used as a
frozen feature extractor for downstream audio classification tasks. This is
relevant for Wren — instead of training a CNN from scratch on log-mel features,
you could:

1. Extract Whisper encoder embeddings for each audio window
2. Train a lightweight classifier on top of those embeddings
3. Get Whisper's acoustic understanding without its under-cutting transcription problem

This gives you the best of both worlds: Whisper's pre-trained acoustic
intelligence + Wren's fast, precise filler-detection classifier.

**References:**
- WhisPAr: https://www.sciencedirect.com/science/article/abs/pii/S0950705124008761
- Whilter: https://arxiv.org/html/2507.21642v1
- Whisper encoder transfer learning discussion: https://github.com/openai/whisper/discussions/1765

---

## 2. Public Datasets for Training

### Datasets directly relevant to filler/disfluency detection

| Dataset | Size | Content | License | Status in Crisp |
|---|---|---|---|---|
| **PodcastFillers** | 145h, 35k fillers | Podcast audio with "uh"/"um" labels, 350+ speakers | CC | ✅ Already using (primary training data) |
| **SEP-28k** | 28k clips (~28h) | Stuttering/disfluency events in podcasts | CC BY-NC (non-commercial) | ✅ Using for hard negatives (partial download, ~240/385 episodes) |
| **FluencyBank** | ~50h | Clinical stuttering interviews, varied disfluencies | Research use | ❌ Not yet used — referenced in SEP-28k repo but not downloaded |

**Action: Download FluencyBank.** It's the natural next data source — more
disfluency variety, different speakers, and it provides additional hard negatives
(music, natural pauses, non-filler disfluencies). The SEP-28k repo's
`fluencybank_episodes.csv` has the episode list and download URLs.

### Datasets for hard negative generation (non-speech / noise)

| Dataset | Size | Content | License | Use case |
|---|---|---|---|---|
| **ESC-50** | 2,000 clips | 50 environmental sound categories (rain, dog bark, engine, etc.) | CC BY-NC | Hard negatives — model should never fire on these |
| **MUSDB18** | ~10h | Separated music tracks (vocals, drums, bass, other) | CC BY-NC 4.0 | Music hard negatives — the exact failure mode (model fires on music) |
| **FMA (Free Music Archive)** | 100k tracks | Full music tracks across genres | CC | Large-scale music negatives |
| **AudioSet** | 5,800h | 632 audio event classes from YouTube | CC BY 4.0 | Massive multi-category audio — filter for non-speech classes |

**Action: Use ESC-50 + MUSDB18 for synthetic hard negatives.** You don't need
labeled music/noise clips from speech datasets — you can mix these directly.
Overlay speech with MUSDB18 music at various SNR levels to simulate the
music-episode failure mode. This gives you unlimited hard negatives.

### Datasets for ASR / transcript generation (for Raven)

| Dataset | Size | Content | License | Use case |
|---|---|---|---|---|
| **LibriSpeech** | 960h | Audiobook readings, clean speech | CC 4.0 | Baseline ASR training |
| **LibriLight** | 60,000h | Unlabeled audiobook audio | CC 4.0 | Pre-training / self-supervised |
| **GigaSpeech** | 10,000h | Multi-domain (podcast, YouTube, audiobook) | Apache 2.0 (scripts), Fair Use (audio) | Real-world speech variety — closest to podcast domain |
| **Common Voice 17** | 26,000h+ | Crowdsourced, 100+ languages | CC 0 (public domain) | Diverse speakers and accents |
| **People's Speech** | 87,000h | Diverse speech from the web | CC BY 4.0 | Large-scale diverse English speech |
| **YouTube-Commons** | Varies | Auto-captioned YouTube audio | Varies | Conversational speech variety |

**Action: GigaSpeech is the most relevant.** It's multi-domain (podcasts, YouTube,
audiobooks) and closest to Crisp's target domain. Use it for Raven's transcript
training if you go the fine-tuning route.

---

## 3. Techniques to Improve Model Accuracy

### 3.1 Proven levers (from the v3 experiments + research)

**A. Scale hard negatives (PROVEN — do this first)**

The v3 experiment showed consistent precision gains from SEP-28k hard negatives.
The bottleneck is data quantity (156 Music + 239 NoSpeech clips). Scaling plan:

1. Download remaining SEP-28k episodes (Kaggle mirror: `ikrbasak/sep-28k`)
2. Add FluencyBank episodes (different speakers, more disfluency types)
3. Generate synthetic hard negatives from ESC-50 + MUSDB18:

   ```python
   # Pseudocode: synthetic music hard negatives
   speech_clip = load_random_speech()
   music_clip = load_random_music()  # from MUSDB18
   mixed = mix_at_snr(speech_clip, music_clip, snr_db=random(0, 20))
   # This is a negative — model should NOT fire on music-overlaid speech
   ```

**B. SpecAugment (HIGH IMPACT, LOW EFFORT)**

The model trains on log-mel spectrograms but does zero augmentation. SpecAugment
is the single most effective augmentation for speech models:

```python
import torchaudio.transforms as T

# Add to the training loop, applied per-batch with probability 0.5
freq_masking = T.FrequencyMasking(freq_mask_param=15)
time_masking = T.TimeMasking(time_mask_param=35)

# Apply: mel = freq_masking(time_masking(mel))
```

This doubles effective dataset size and improves robustness to speaker/mic
variation. Proven on Whisper, wav2vec2, and CNN audio classifiers.

**C. Mixup training (MODERATE IMPACT)**

Mix pairs of training examples by linearly interpolating both the audio and the
labels. This is particularly effective for the filler/natural boundary:

```python
# During training, with probability 0.3:
lam = np.random.beta(0.2, 0.2)
mixed_mel = lam * mel_a + (1 - lam) * mel_b
mixed_label = lam * label_a + (1 - lam) * label_b
```

This helps the model learn smoother decision boundaries at the
removable/natural border — exactly the gray zone that v3's re-labeling
experiment tried to address.

### 3.2 Architecture improvements for Wren

**D. Dilated TCN depth — increase receptive field**

v2's WrenSeq uses a dilated TCN with ~2.5s receptive field. For detecting
whether a filler is removable (which depends on sentence-level context),
a larger receptive field helps. Consider:
- Increase dilation pattern to cover ~5s (doubles context at minimal param cost)
- Add a second TCN stack with larger dilation for hierarchical context

**E. Multi-scale feature aggregation**

Instead of a single log-mel configuration (64 mels, 25 frames), use multiple
scales:
- Fine: 128 mels, 0.1s windows (captures spectral detail)
- Medium: 64 mels, 0.25s windows (current — captures filler identity)
- Coarse: 32 mels, 1.0s windows (captures surrounding context)

Concatenate features from all three scales. This helps the model distinguish
isolated fillers (removable) from embedded ones (natural) by giving it both
local and global context.

### 3.3 Training improvements

**F. Focal Loss instead of BCEWithLogitsLoss**

The current training uses BCE with `pos_weight` to handle class imbalance. Focal
Loss is better suited when the hard examples (boundary fillers, non-speech) are
the ones that matter:

```python
class FocalLoss(nn.Module):
    def __init__(self, alpha=0.25, gamma=2.0):
        super().__init__()
        self.alpha = alpha
        self.gamma = gamma

    def forward(self, logits, targets):
        bce = F.binary_cross_entropy_with_logits(logits, targets, reduction='none')
        pt = torch.exp(-bce)
        loss = self.alpha * (1 - pt) ** self.gamma * bce
        return loss.mean()
```

Focal Loss down-weights easy examples (clear speech, clear fillers) and focuses
training on the hard ones (boundary fillers, non-speech, music) — directly
targeting the failure modes identified in the v3 experiments.

**G. Cosine annealing with warm restarts**

The current training uses a fixed learning rate or simple decay. Cosine
annealing with warm restarts (SGDR) helps the model escape local minima and find
better solutions:

```python
scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
    optimizer, T_0=10, T_mult=2, eta_min=1e-6
)
```

**H. Test-time augmentation (TTA)**

At inference, run the model on slightly augmented versions of the input and
average the predictions:
- Original audio
- Pitch-shifted by +2 semitones
- Pitch-shifted by -2 semitones
- Time-stretched by 1.1x

This costs 4x inference time but improves precision. For Crisp's use case
(on-device, real-time), TTA may be too expensive — but it's valuable for
generating high-quality pseudo-labels for the next training round.

### 3.4 Raven-specific recommendations

**I. Whisper encoder + lightweight classifier (recommended architecture)**

For Raven, instead of training a full ASR model + removability classifier:

1. Use Whisper's encoder (frozen, no fine-tuning) to extract embeddings
2. Feed embeddings into a small transformer or TCN classifier
3. Train the classifier on the "removable vs natural" labels

This gives Raven Whisper's acoustic understanding (it knows what speech sounds
like, what words are, where boundaries are) without inheriting its under-cutting
transcription behavior. The classifier learns the editorial decision on top of
rich features.

Estimated size: Whisper encoder (~32M params for tiny) + classifier (~500K
params) = manageable for a "heavier" tier that runs on-device or on-cloud.

**J. Two-pass inference for Raven**

1. First pass: Wren (fast, audio-only) identifies candidate filler regions
2. Second pass: Raven (slow, accurate) confirms/removes based on transcript context

This way Raven only runs on ~1-5% of the audio (the candidate regions), keeping
total inference fast. Wren acts as a proposal generator, Raven as the editor.

---

## 4. Implementation Priority

| Priority | Action | Effort | Expected impact |
|---|---|---|---|
| **P0** | Scale hard negatives (SEP-28k + FluencyBank + synthetic ESC-50/MUSDB18) | Medium | **High** — proven lever, directly addresses the music/noise false-positive problem |
| **P0** | Add SpecAugment to training loop | Low (~5 lines) | **High** — free robustness improvement, proven on every speech model |
| **P1** | Download FluencyBank dataset | Low | **Medium** — more disfluency variety, more speakers |
| **P1** | Focal Loss for hard-example focus | Low (~20 lines) | **Medium** — targets the boundary/non-speech examples that matter |
| **P2** | Mixup training for smoother boundaries | Low | **Medium** — helps the removable/natural gray zone |
| **P2** | Cosine annealing scheduler | Low (~3 lines) | **Low-Medium** — better convergence |
| **P3** | Whisper encoder features for Raven | High (new architecture) | **High** — but requires significant work |
| **P3** | Two-pass inference (Wren proposes, Raven confirms) | High | **High** — but depends on Raven existing first |
| **P4** | Multi-scale feature aggregation | Medium | **Medium** — architectural change, needs retraining + export |
| **P4** | Increase TCN receptive field to ~5s | Low | **Low-Medium** — more context, marginal gains |

---

## 5. Summary

The v3 experiments confirmed the right direction: **data over architecture**.
The hard-negative approach works, and the next step is simply more of it — more
non-speech negatives from more sources, plus synthetic generation from music/noise
datasets.

For the immediate next model (Wren v0.0.10):
1. Scale hard negatives (SEP-28k + FluencyBank + synthetic)
2. Add SpecAugment
3. Retrain → publish to nightly → validate on real footage

For the longer-term Raven tier:
1. Use Whisper encoder as frozen feature extractor
2. Train lightweight removability classifier on top
3. Implement two-pass inference (Wren proposes, Raven confirms)

---

*Research by Scarlet Speedster — automated analysis for the Crisp project*
*Date: 2026-06-23*
