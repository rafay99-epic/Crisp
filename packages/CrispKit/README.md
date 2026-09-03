# CrispKit

The platform-free half of Crisp's cleaning engine, in Swift.

Crisp's engine is a Python program that orchestrates subprocesses: `ffmpeg`,
`ffprobe`, `whisper-cli`, `crisp-filler`, `crisp-embed`. iOS has no multiprocess at
all (PEP 730: `fork` and `spawn` exist in the API, but calling them stops the calling
process and never starts the new one), so none of it can run on iPhone or iPad. The
fix is not to port Python; it is to move the engine into Swift and replace the
binaries with Apple frameworks.

This package is the first step: the part of the engine that was never about media in
the first place.

## What is in here

| Module | Ported from | Does |
|---|---|---|
| `Config` | `crisp/config.py` | Tunable defaults and the retake sensitivity presets |
| `FillerVocabulary` | `crisp/text.py` | Whole-token filler matching (um / uh / hmm) |
| `Retake` | `crisp/retake.py` | Finds a flubbed take the speaker immediately redid |
| `SequenceRatio` | `difflib` | Ratcliff-Obershelp similarity, matching Python exactly |
| `Captions` | `crisp/captions.py` | Re-times words onto the cut timeline, writes SRT / WebVTT |
| `FrameRate` | `crisp/framerate.py` | VFR detection and the constant-rate target |
| `Waveform` | `crisp/waveform.py` | Peak buckets and cut flags for the UI |
| `TimeSpan` | (new) | The value type the whole engine speaks in |

Everything is a pure function over values. No ffmpeg, no subprocesses, no AppKit, no
file system beyond path arithmetic. The package declares iOS 18 as a deployment
target specifically so a macOS-only API cannot creep in unnoticed.

## Parity, not plausibility

CrispKit replaces working code, so "looks right" is not the bar. `Tools/generate-fixtures.py`
runs the **Python** implementation over a corpus of inputs and writes the answers to
`Tests/CrispKitTests/Fixtures/*.json`. The Swift tests assert against those files.

That buys two things. CI needs no Python to check the Swift side, and the expected
values are reviewable in the diff rather than hidden in a test helper. CI also
re-runs the generator and fails if the output moves, so a change to `config.py` or a
cut decision on the Python side cannot silently drift away from the Swift port while
both exist.

Regenerate after any change to the Python engine:

```sh
python3 packages/CrispKit/Tools/generate-fixtures.py
```

## Tests

```sh
cd packages/CrispKit && swift test
```

`ParityTests` compares against the fixtures. `BehaviourTests` covers the contracts
fixtures cannot reach: value-type semantics, degenerate inputs, and invariants the
media layer will depend on (removal spans are ordered and non-overlapping, a semantic
judge can never veto a pause-anchored cut, `nil` silences and empty silences are
different inputs).

## Not wired in yet

The macOS app still drives the Python engine. This package is built and tested in
isolation on purpose: the risky work is the media layer (AVFoundation replacing
ffmpeg), and it should land on a core that is already proven correct. See the
migration plan for the phase order.

## One notable gotcha

`difflib.SequenceMatcher.ratio()` is **not symmetric** — it depends on argument
order. Retake detection's token threshold (0.85) is tuned against difflib's specific
numbers, so `SequenceRatio` reproduces the algorithm rather than substituting a
Levenshtein or LCS ratio, and the asymmetry is pinned by a test rather than
"corrected".
