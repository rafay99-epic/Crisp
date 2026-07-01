# packages/engine — the Crisp cleaning core

The shared, UI-agnostic core that both frontends drive as a subprocess:

- `apps/desktop` (macOS, Swift) — bundles this into `Contents/Resources/engine/`
- `apps/desktop-win` (Windows, .NET) — bundles this into `publish/engine/`

The core knows nothing about any UI. It speaks NDJSON on stdout (`--ndjson`) for
the apps and prints `→` lines in the human CLI mode. Tweak the core here without
touching either UI; the apps re-bundle it verbatim at build time.

## Layout

- `clean_video.py` — thin CLI wrapper (argparse + NDJSON/human emit).
- `crisp/` — the engine package: `config`, `tools`, `text`, `detect`, `edit`,
  `encode`, `pipeline`, … Library users do `from crisp import clean_video`.
- `tests/` — stdlib-only unit tests (no ffmpeg/whisper), CI-gated.
- `models/` — the whisper speech model, downloaded by `setup.sh` (gitignored).

Pure Python **stdlib** — no pip dependencies. It shells out to **ffmpeg** and
**whisper.cpp**, resolved from `CRISP_FFMPEG` / `CRISP_FFPROBE` / `CRISP_WHISPER`
(set by the apps to their bundled binaries), falling back to `PATH`.

## Run the tests

```sh
cd packages/engine
python3 -m unittest discover -s tests -t .
```

## Drive it directly

```sh
python3 clean_video.py input.mp4 --no-fillers          # pauses only, no model
python3 clean_video.py input.mp4 --ndjson              # machine-readable stream
```
